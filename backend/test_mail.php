<?php

require 'vendor/autoload.php';

use PHPMailer\PHPMailer\PHPMailer;
use PHPMailer\PHPMailer\Exception;
use PHPMailer\PHPMailer\SMTP;

$mail = new PHPMailer(true);

try {

    // DEBUG TEMPORAL
    $mail->SMTPDebug = SMTP::DEBUG_SERVER;
    $mail->Debugoutput = 'echo';

    // SMTP
    $mail->isSMTP();

    $mail->Host = 'smtp.gmail.com';
    $mail->SMTPAuth = true;

    $mail->Username = 'jnegretep24@gmail.com';

    // IMPORTANTE:
    // Aquí debe ir la CONTRASEÑA DE APLICACIÓN de Google,
    // NO la contraseña normal de Gmail.
    $mail->Password = 'rwre txva dnpr nrzl';

    $mail->SMTPSecure = PHPMailer::ENCRYPTION_STARTTLS;
    $mail->Port = 587;

    // Remitente
    $mail->setFrom(
        'jnegretep24@gmail.com',
        'PrepSaber'
    );

    // Destinatario
    $mail->addAddress(
        'saberplus2026@gmail.com'
    );

    // Mensaje
    $mail->isHTML(true);
    $mail->Subject = 'Prueba de correo PrepSaber';
    $mail->Body = '
        <h2>Prueba de correo PrepSaber</h2>
        <p>Si recibes este mensaje, SMTP está funcionando correctamente.</p>
    ';

    $mail->send();

    echo PHP_EOL;
    echo "====================================" . PHP_EOL;
    echo "CORREO ENVIADO CORRECTAMENTE" . PHP_EOL;
    echo "====================================" . PHP_EOL;

} catch (Exception $e) {

    echo PHP_EOL;
    echo "====================================" . PHP_EOL;
    echo "ERROR SMTP" . PHP_EOL;
    echo "====================================" . PHP_EOL;

    echo "ErrorInfo: " . $mail->ErrorInfo . PHP_EOL;
    echo "Exception: " . $e->getMessage() . PHP_EOL;
}