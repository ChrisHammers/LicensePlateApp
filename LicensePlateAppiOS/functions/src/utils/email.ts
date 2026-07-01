import nodemailer from "nodemailer";

export interface SmtpConfig {
  host: string;
  port: number;
  secure: boolean;
  user: string;
  pass: string;
}

export interface SendEmailParams {
  smtp: SmtpConfig;
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

/**
 * Send a transactional email through your existing SMTP mailbox.
 * Works with Google Workspace, Microsoft 365, Zoho, cPanel hosting mail, etc.
 */
export async function sendTransactionalEmail(
  params: SendEmailParams
): Promise<SendEmailResult> {
  const transporter = nodemailer.createTransport({
    host: params.smtp.host,
    port: params.smtp.port,
    secure: params.smtp.secure,
    auth: {
      user: params.smtp.user,
      pass: params.smtp.pass,
    },
  });

  const info = await transporter.sendMail({
    from: params.from,
    to: params.to,
    subject: params.subject,
    html: params.html,
    text: params.text,
    ...(params.replyTo ? { replyTo: params.replyTo } : {}),
  });

  return { providerMessageId: info.messageId ?? null };
}
