/**
 * Minimal in-memory Firestore stand-in for vitest.
 *
 * Covers exactly the surface the account-deletion de-identification pipeline uses:
 * doc/collection refs, get/set/update/delete, `where` equality (including dotted map paths),
 * `orderBy(documentId)` + `startAfter` + `limit`, `listDocuments`, `collectionGroup`, and
 * `WriteBatch` with a 500-op cap. Paths are the real slash-separated Firestore paths, so a
 * "does any doc anywhere still name this uid" scan over `store` is a faithful residue check.
 *
 * `where` also supports the range operators (`>=`, `<`, `>`, `<=`) so the username *prefix*
 * scan in `userSearch.ts` — the search path that reads user docs directly and therefore
 * cannot be protected by index removal alone (COPPA FR-9) — can be exercised end to end.
 */

const MAX_BATCH_OPS = 500;

type Data = Record<string, unknown>;

function isPlainObject(value: unknown): value is Data {
  return !!value && typeof value === "object" && !Array.isArray(value);
}

function deepClone<T>(value: T): T {
  return value === undefined ? value : (JSON.parse(JSON.stringify(value)) as T);
}

/** Firestore `set({merge:true})` deep-merges nested maps; `update()` replaces them. */
function deepMerge(base: Data, patch: Data): Data {
  const out: Data = { ...base };
  for (const [key, value] of Object.entries(patch)) {
    out[key] = isPlainObject(value) && isPlainObject(out[key])
      ? deepMerge(out[key] as Data, value)
      : value;
  }
  return out;
}

function readPath(data: Data, path: string): unknown {
  return path.split(".").reduce<unknown>(
    (acc, segment) => (isPlainObject(acc) ? acc[segment] : undefined),
    data
  );
}

export type FakeFilterOp = "==" | ">=" | ">" | "<=" | "<";

/** Range operators never match a missing field, matching Firestore's index semantics. */
function matchesFilter(actual: unknown, op: FakeFilterOp, value: unknown): boolean {
  if (op === "==") return actual === value;
  if (actual === undefined || actual === null) return false;
  const left = actual as never;
  const right = value as never;
  if (op === ">=") return left >= right;
  if (op === ">") return left > right;
  if (op === "<=") return left <= right;
  return left < right;
}

export class FakeFirestore {
  /** Full doc path -> data. A doc exists iff it has an entry here. */
  readonly store = new Map<string, Data>();
  /** Number of committed batches, for asserting a re-run is a genuine no-op. */
  writeCount = 0;
  private autoIdCounter = 0;

  allocateAutoId(): string {
    this.autoIdCounter += 1;
    return `auto_${String(this.autoIdCounter).padStart(4, "0")}`;
  }

  collection(id: string): FakeCollectionRef {
    return new FakeCollectionRef(this, id, null);
  }

  collectionGroup(id: string): FakeQuery {
    return new FakeQuery(this, { collectionGroupId: id });
  }

  batch(): FakeWriteBatch {
    return new FakeWriteBatch(this);
  }

  /**
   * Single-threaded stand-in for `runTransaction`. Reads see committed state; writes are
   * queued and applied together when the callback resolves, matching Firestore's
   * all-reads-before-writes shape. There is no contention to retry in a test, so the
   * callback runs exactly once — which is what makes the FR-47 rate-limit counter
   * (`inviteRateLimit.ts`) assertable.
   */
  async runTransaction<T>(
    updateFunction: (transaction: FakeTransaction) => Promise<T>
  ): Promise<T> {
    const transaction = new FakeTransaction(this);
    const result = await updateFunction(transaction);
    transaction.commit();
    return result;
  }

  /** Seed a document (test helper — bypasses the write counter). */
  seed(path: string, data: Data): void {
    this.store.set(path, deepClone(data));
  }

  docPathsMatching(predicate: (path: string, data: Data) => boolean): string[] {
    return [...this.store.entries()]
      .filter(([path, data]) => predicate(path, data))
      .map(([path]) => path)
      .sort();
  }
}

export class FakeDocumentRef {
  constructor(
    private readonly db: FakeFirestore,
    readonly path: string,
    readonly parent: FakeCollectionRef
  ) {}

  get id(): string {
    return this.path.slice(this.path.lastIndexOf("/") + 1);
  }

  collection(id: string): FakeCollectionRef {
    return new FakeCollectionRef(this.db, id, this);
  }

  async get(): Promise<FakeDocumentSnapshot> {
    const data = this.db.store.get(this.path);
    return new FakeDocumentSnapshot(this, data ? deepClone(data) : undefined);
  }

  async set(data: Data, options?: { merge?: boolean }): Promise<void> {
    this.applySet(data, options?.merge === true);
    this.db.writeCount += 1;
  }

  async update(data: Data): Promise<void> {
    this.applyUpdate(data);
    this.db.writeCount += 1;
  }

  async delete(): Promise<void> {
    this.applyDelete();
    this.db.writeCount += 1;
  }

  applySet(data: Data, merge: boolean): void {
    const existing = this.db.store.get(this.path);
    this.db.store.set(
      this.path,
      merge && existing ? deepMerge(existing, deepClone(data)) : deepClone(data)
    );
  }

  applyUpdate(data: Data): void {
    const existing = this.db.store.get(this.path);
    if (!existing) {
      throw new Error(`update() on missing document: ${this.path}`);
    }
    this.db.store.set(this.path, { ...existing, ...deepClone(data) });
  }

  applyDelete(): void {
    this.db.store.delete(this.path);
  }
}

export class FakeDocumentSnapshot {
  constructor(
    readonly ref: FakeDocumentRef,
    private readonly _data: Data | undefined
  ) {}

  get id(): string {
    return this.ref.id;
  }

  get exists(): boolean {
    return this._data !== undefined;
  }

  data(): Data | undefined {
    return this._data;
  }
}

export class FakeCollectionRef {
  readonly path: string;

  constructor(
    private readonly db: FakeFirestore,
    readonly id: string,
    /** Parent document, or null for a root collection. */
    readonly parent: FakeDocumentRef | null
  ) {
    this.path = parent ? `${parent.path}/${id}` : id;
  }

  /**
   * `doc()` with no id allocates one, as Firestore does — `tripInvites.ts` and `family.ts`
   * both mint refs that way. Without this every such ref collapsed onto the literal path
   * ".../undefined", so a test creating two documents silently saw one.
   */
  doc(id?: string): FakeDocumentRef {
    const docId = id ?? this.db.allocateAutoId();
    return new FakeDocumentRef(this.db, `${this.path}/${docId}`, this);
  }

  async add(data: Data): Promise<FakeDocumentRef> {
    const ref = this.doc(this.db.allocateAutoId());
    ref.applySet(data, false);
    this.db.writeCount += 1;
    return ref;
  }

  where(field: string, op: FakeFilterOp, value: unknown): FakeQuery {
    return new FakeQuery(this.db, { collectionPath: this.path }).where(field, op, value);
  }

  orderBy(field: unknown): FakeQuery {
    return new FakeQuery(this.db, { collectionPath: this.path }).orderBy(field);
  }

  limit(n: number): FakeQuery {
    return new FakeQuery(this.db, { collectionPath: this.path }).limit(n);
  }

  async get(): Promise<FakeQuerySnapshot> {
    return new FakeQuery(this.db, { collectionPath: this.path }).get();
  }

  async listDocuments(): Promise<FakeDocumentRef[]> {
    const prefix = `${this.path}/`;
    const ids = new Set<string>();
    for (const path of this.db.store.keys()) {
      if (!path.startsWith(prefix)) continue;
      // Direct children only: the remainder must be a single segment.
      const rest = path.slice(prefix.length);
      ids.add(rest.split("/")[0]);
    }
    return [...ids].sort().map((id) => this.doc(id));
  }
}

interface QuerySource {
  collectionPath?: string;
  collectionGroupId?: string;
}

export class FakeQuery {
  private filters: { field: string; op: FakeFilterOp; value: unknown }[] = [];
  private limitCount: number | null = null;
  private startAfterId: string | null = null;

  constructor(
    private readonly db: FakeFirestore,
    private readonly source: QuerySource
  ) {}

  private clone(): FakeQuery {
    const next = new FakeQuery(this.db, this.source);
    next.filters = [...this.filters];
    next.limitCount = this.limitCount;
    next.startAfterId = this.startAfterId;
    return next;
  }

  where(field: string, op: FakeFilterOp, value: unknown): FakeQuery {
    const next = this.clone();
    next.filters.push({ field, op, value });
    return next;
  }

  /** Only documentId ordering is used by the pipeline; results are already id-sorted. */
  orderBy(_field: unknown): FakeQuery {
    return this.clone();
  }

  limit(n: number): FakeQuery {
    const next = this.clone();
    next.limitCount = n;
    return next;
  }

  startAfter(id: string): FakeQuery {
    const next = this.clone();
    next.startAfterId = id;
    return next;
  }

  private matchesSource(path: string): boolean {
    const lastSlash = path.lastIndexOf("/");
    const collectionPath = path.slice(0, lastSlash);
    if (this.source.collectionPath !== undefined) {
      return collectionPath === this.source.collectionPath;
    }
    const collectionId = collectionPath.slice(collectionPath.lastIndexOf("/") + 1);
    return collectionId === this.source.collectionGroupId;
  }

  async get(): Promise<FakeQuerySnapshot> {
    let paths = [...this.db.store.keys()].filter((path) => this.matchesSource(path)).sort();

    paths = paths.filter((path) => {
      const data = this.db.store.get(path)!;
      return this.filters.every((f) =>
        matchesFilter(readPath(data, f.field), f.op, f.value)
      );
    });

    if (this.startAfterId !== null) {
      const after = this.startAfterId;
      paths = paths.filter((path) => path.slice(path.lastIndexOf("/") + 1) > after);
    }
    if (this.limitCount !== null) {
      paths = paths.slice(0, this.limitCount);
    }

    const docs = paths.map((path) => {
      const lastSlash = path.lastIndexOf("/");
      const collectionPath = path.slice(0, lastSlash);
      const ref = refForPath(this.db, collectionPath).doc(path.slice(lastSlash + 1));
      return new FakeDocumentSnapshot(ref, deepClone(this.db.store.get(path)!));
    });
    return new FakeQuerySnapshot(docs);
  }
}

export class FakeQuerySnapshot {
  constructor(readonly docs: FakeDocumentSnapshot[]) {}

  get empty(): boolean {
    return this.docs.length === 0;
  }

  get size(): number {
    return this.docs.length;
  }

  forEach(callback: (doc: FakeDocumentSnapshot) => void): void {
    this.docs.forEach((doc) => callback(doc));
  }
}

export class FakeTransaction {
  private ops: (() => void)[] = [];

  constructor(private readonly db: FakeFirestore) {}

  async get(ref: FakeDocumentRef): Promise<FakeDocumentSnapshot>;
  async get(ref: FakeQuery): Promise<FakeQuerySnapshot>;
  async get(ref: FakeDocumentRef | FakeQuery): Promise<unknown> {
    return ref.get();
  }

  set(ref: FakeDocumentRef, data: Data, options?: { merge?: boolean }): FakeTransaction {
    this.ops.push(() => ref.applySet(data, options?.merge === true));
    return this;
  }

  update(ref: FakeDocumentRef, data: Data): FakeTransaction {
    this.ops.push(() => ref.applyUpdate(data));
    return this;
  }

  delete(ref: FakeDocumentRef): FakeTransaction {
    this.ops.push(() => ref.applyDelete());
    return this;
  }

  /** Applies the queued writes. Called by `FakeFirestore.runTransaction`. */
  commit(): void {
    for (const op of this.ops) op();
    this.db.writeCount += this.ops.length;
    this.ops = [];
  }
}

export class FakeWriteBatch {
  private ops: (() => void)[] = [];

  constructor(private readonly db: FakeFirestore) {}

  private push(op: () => void): void {
    if (this.ops.length >= MAX_BATCH_OPS) {
      throw new Error(`WriteBatch exceeded ${MAX_BATCH_OPS} operations`);
    }
    this.ops.push(op);
  }

  set(ref: FakeDocumentRef, data: Data, options?: { merge?: boolean }): void {
    this.push(() => ref.applySet(data, options?.merge === true));
  }

  update(ref: FakeDocumentRef, data: Data): void {
    this.push(() => ref.applyUpdate(data));
  }

  delete(ref: FakeDocumentRef): void {
    this.push(() => ref.applyDelete());
  }

  async commit(): Promise<void> {
    for (const op of this.ops) op();
    this.db.writeCount += this.ops.length;
    this.ops = [];
  }
}

/** Rebuild a collection ref from a slash-separated collection path. */
function refForPath(db: FakeFirestore, collectionPath: string): FakeCollectionRef {
  const segments = collectionPath.split("/");
  let collection = db.collection(segments[0]);
  for (let i = 1; i < segments.length; i += 2) {
    collection = collection.doc(segments[i]).collection(segments[i + 1]);
  }
  return collection;
}
