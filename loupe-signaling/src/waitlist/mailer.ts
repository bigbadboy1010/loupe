import type { WaitlistEntry } from "./store.js";

export interface Mailer {
  sendConfirmation(entry: WaitlistEntry): Promise<void>;
}

/**
 * No-op mailer used until SMTP / transactional-email credentials are wired up.
 * Logs the would-be email so operators can verify shape during local development.
 *
 * Replace with `SmtpMailer` (nodemailer) or a transactional provider (Postmark, SES, Brevo)
 * in Sprint 2 once `WAITLIST_SMTP_URL` is set. The contract is intentionally small so the
 * swap is mechanical.
 */
export class LoggingMailer implements Mailer {
  public constructor(private readonly logger: { info: (obj: unknown, msg: string) => void }) {}

  public async sendConfirmation(entry: WaitlistEntry): Promise<void> {
    this.logger.info(
      {
        to: entry.email,
        subject: "You're on the Loupe waitlist",
        body: confirmationBody(entry),
      },
      "waitlist.mailer.stub",
    );
  }
}

function confirmationBody(entry: WaitlistEntry): string {
  return [
    `Hi,`,
    ``,
    `You're on the Loupe waitlist. We'll email you again when the beta opens — no drip`,
    `campaign, no marketing automation. Reply to this email if you'd like to be removed`,
    `or if you have questions.`,
    ``,
    `Reference: ${entry.source} @ ${entry.referrer}`,
    ``,
    `— Loupe`,
  ].join("\n");
}
