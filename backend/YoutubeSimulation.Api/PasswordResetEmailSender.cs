using System.Net;
using System.Net.Mail;

public sealed class PasswordResetEmailSender(IConfiguration configuration)
{
    private readonly string _host = configuration["Email:SmtpHost"] ?? "";
    private readonly int _port = configuration.GetValue("Email:SmtpPort", 587);
    private readonly string _username = configuration["Email:SmtpUsername"] ?? "";
    private readonly string _password = configuration["Email:SmtpPassword"] ?? "";
    private readonly string _from = configuration["Email:FromAddress"] ?? "";
    private readonly string _fromName = configuration["Email:FromName"] ?? "YouTube Simulation";
    private readonly bool _enableSsl = configuration.GetValue("Email:EnableSsl", true);

    public bool IsConfigured =>
        !string.IsNullOrWhiteSpace(_host)
        && _port is > 0 and <= 65535
        && MailAddress.TryCreate(_from, out _)
        && (_username.Length == 0) == (_password.Length == 0);

    public async Task SendPasswordResetAsync(string email, string token, CancellationToken ct)
    {
        if (!IsConfigured)
            throw new InvalidOperationException("Password-reset email delivery is not configured.");

        using var message = new MailMessage
        {
            From = new MailAddress(_from, _fromName),
            Subject = "Đặt lại mật khẩu",
            Body = $"""
                <p>Bạn vừa yêu cầu đặt lại mật khẩu.</p>
                <p>Mã đặt lại của bạn là:</p>
                <p><strong>{WebUtility.HtmlEncode(token)}</strong></p>
                <p>Mã có hiệu lực trong 30 phút và chỉ sử dụng được một lần. Nếu bạn không yêu cầu, hãy bỏ qua email này.</p>
                """,
            IsBodyHtml = true
        };
        message.To.Add(email);

        using var client = new SmtpClient(_host, _port)
        {
            EnableSsl = _enableSsl,
            UseDefaultCredentials = false,
            DeliveryMethod = SmtpDeliveryMethod.Network,
            Timeout = 30_000
        };
        if (_username.Length > 0)
            client.Credentials = new NetworkCredential(_username, _password);

        await client.SendMailAsync(message, ct);
    }
}
