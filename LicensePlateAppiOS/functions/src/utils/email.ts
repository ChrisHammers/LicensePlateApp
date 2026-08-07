export interface SendEmailParams {
  apiKey: string;
  from: string;
  to: string;
  subject: string;
  html: string;
  text: string;
  replyTo?: string;
}

export interface SendEmailResult {
  providerMessageId: string | null;
}

interface ResendErrorBody {
  message?: string;
}

/**
 * Send a transactional email via Resend.
 * `from` must use a verified domain/sender in the Resend dashboard.
 */
export async function sendTransactionalEmail(
  params: SendEmailParams
): Promise<SendEmailResult> {
  const response = await fetch("https://api.resend.com/emails", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${params.apiKey}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      from: params.from,
      to: [params.to],
      subject: params.subject,
      html: params.html,
      text: params.text,
      ...(params.replyTo ? { reply_to: params.replyTo } : {}),
    }),
  });

  const body = (await response.json()) as { id?: string } & ResendErrorBody;
  if (!response.ok) {
    throw new Error(body.message || `Resend API error (${response.status})`);
  }

  return { providerMessageId: body.id ?? null };
}
