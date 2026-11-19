<?php
/**
 * wompi_return.php
 * Página de aterrizaje tras el pago
 */
$id = $_GET['id'] ?? null; // Wompi envía el ID de transacción por URL
?>
<!DOCTYPE html>
<html lang="es">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Estado del Pago - PrepSaber</title>
    <link href="https://cdn.jsdelivr.net/npm/bootstrap@5.3.0/dist/css/bootstrap.min.css" rel="stylesheet">
    <style>
        body { background-color: #f8f9fa; font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif; }
        .card { border: none; border-radius: 15px; box-shadow: 0 4px 15px rgba(0,0,0,0.1); }
        .btn-custom { background-color: #4A90E2; color: white; border-radius: 25px; padding: 10px 30px; text-decoration: none; }
        .logo { max-width: 180px; margin-bottom: 20px; }
    </style>
</head>
<body>
    <div class="container vh-100 d-flex align-items-center justify-content-center">
        <div class="card p-5 text-center" style="max-width: 450px; width: 100%;">
            <img src="http://corpoinstel.edu.co/api/prepsaber/backend/logo.jpg" alt="Logo" class="logo mx-auto">
            
            <div id="loading">
                <div class="spinner-border text-primary" role="status"></div>
                <p class="mt-3">Verificando tu pago...</p>
            </div>

            <div id="content" style="display:none;">
                <h2 id="title" class="mb-3"></h2>
                <p id="message" class="text-muted mb-4"></p>
                <a href="prepsaber://payment_status" class="btn-custom">Volver a la App</a>
            </div>
        </div>
    </div>

    <script>
        // Consultar el estado real de la transacción a la API de Wompi
        const transactionId = "<?php echo $id; ?>";
        
        if (!transactionId) {
            showResult("Error", "No se encontró la información del pago.", "text-danger");
        } else {
            fetch(`https://production.wompi.co/v1/transactions/${transactionId}`)
                .then(response => response.json())
                .then(res => {
                    const status = res.data.status;
                    if (status === 'APPROVED') {
                        showResult("¡Pago Exitoso!", "Tu cuenta ha sido activada como Premium. Ya puedes disfrutar de todo el contenido.", "text-success");
                    } else if (status === 'PENDING') {
                        showResult("Pago Pendiente", "Tu pago se está procesando. Te avisaremos cuando finalice.", "text-warning");
                    } else {
                        showResult("Pago No Realizado", "La transacción fue rechazada o cancelada.", "text-danger");
                    }
                })
                .catch(err => {
                    showResult("Aviso", "Pago procesado. Revisa tu perfil en la app.", "text-primary");
                });
        }

        function showResult(title, msg, colorClass) {
            document.getElementById('loading').style.display = 'none';
            document.getElementById('content').style.display = 'block';
            document.getElementById('title').innerText = title;
            document.getElementById('title').classList.add(colorClass);
            document.getElementById('message').innerText = msg;
        }
    </script>
</body>
</html>