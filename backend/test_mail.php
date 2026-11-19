<?php
// test_mail.php — Script aislado para probar el envío de correo con PHPMailer

ini_set('display_errors', 1);
error_reporting(E_ALL);

require __DIR__ . '/vendor/autoload.php';

use PHPMailer\PHPMailer\PHPMailer;
use PHPMailer\PHPMailer\Exception as PHPMailerException;

$mail = new PHPMailer(true);

try {
    // Configuración del servidor SMTP (Puedes cambiar los valores o quemarlos temporalmente para probar)
    $mail->isSMTP();
    $mail->Host       = 'smtp.gmail.com';
    $mail->SMTPAuth   = true;
    
    // REEMPLAZA ESTOS DOS DATOS CON LOS REALES PARA LA PRUEBA:
    $mail->Username   = 'Saberplus2026@gmail.com';
    $mail->Password   = 'cnejjghxyavzzalz'; 
    
    $mail->SMTPSecure = PHPMailer::ENCRYPTION_STARTTLS;
    $mail->Port       = 587;
    $mail->CharSet    = 'UTF-8';

    // Remitente y destinatario (puedes poner tu propio correo personal para recibir la prueba)
    $mail->setFrom('Saberplus2026@gmail.com', 'Equipo de soporte Saber+');
    $mail->addAddress('jnegretep24@gmail.com', 'Prueba Saber+');

    // Contenido del mensaje
    $mail->isHTML(true);
    $mail->Subject = 'Prueba exitosa de PHPMailer - Saber+';
    $mail->Body    = "<h2>¡Funciona!</h2><p>Este es un correo de prueba enviado directamente desde el servidor para verificar la autenticación SMTP.</p>";
    $mail->AltBody = "¡Funciona! Este es un correo de prueba enviado directamente desde el servidor.";

    $mail->send();
    echo "<h2 style='color: green;'>¡Correo enviado con éxito! Revisa tu bandeja de entrada.</h2>";

} catch (PHPMailerException $e) {
    echo "<h2 style='color: red;'>Error al enviar el correo:</h2>";
    echo "<pre>" . htmlspecialchars($mail->ErrorInfo) . "</pre>";
}