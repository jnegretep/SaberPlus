<?php
require_once 'models/UserPlan.php';

class AccessController {
    private $userPlan;
    
    public function __construct($db) {
        $this->userPlan = new UserPlan($db);
    }
    
    public function checkAccess() {
        $userId = $_POST['user_id'] ?? $_GET['user_id'] ?? 0;
        $contentType = $_POST['content_type'] ?? $_GET['content_type'] ?? '';
        $contentId = $_POST['content_id'] ?? $_GET['content_id'] ?? 0;
        
        if (!$userId || !$contentType || !$contentId) {
            return json_encode([
                'success' => false,
                'error' => 'Faltan parámetros'
            ]);
        }
        
        $canAccess = $this->userPlan->canAccessContent($userId, $contentType, $contentId);
        
        return json_encode([
            'success' => true,
            'can_access' => $canAccess,
            'user_id' => $userId
        ]);
    }
    
    public function getUserPlanInfo() {
        $userId = $_POST['user_id'] ?? $_GET['user_id'] ?? 0;
        
        if (!$userId) {
            return json_encode(['success' => false, 'error' => 'Falta user_id']);
        }
        
        $planInfo = $this->userPlan->getUserAccess($userId);
        
        // Verificar si es early bird
        if ($planInfo['access_level'] == 'free') {
            $newStatus = $this->userPlan->checkEarlyUserStatus($userId);
            if ($newStatus != 'free') {
                $planInfo = $this->userPlan->getUserAccess($userId);
            }
        }
        
        return json_encode([
            'success' => true,
            'plan' => $planInfo
        ]);
    }
    
    public function processPayment() {
        $userId = $_POST['user_id'] ?? 0;
        $paymentData = [
            'payment_method' => $_POST['payment_method'] ?? '',
            'transaction_id' => $_POST['transaction_id'] ?? '',
            'amount' => $_POST['amount'] ?? 0,
            'receipt_data' => $_POST['receipt_data'] ?? ''
        ];
        
        if (!$userId || empty($paymentData['payment_method'])) {
            return json_encode([
                'success' => false,
                'error' => 'Datos de pago incompletos'
            ]);
        }
        
        $result = $this->userPlan->upgradeToPremium($userId, $paymentData);
        
        return json_encode($result);
    }
    
    public function getPremiumPrice() {
        $query = "SELECT config_value FROM system_config 
                  WHERE config_key = 'premium_price'";
        $stmt = $this->conn->prepare($query);
        $stmt->execute();
        $result = $stmt->get_result();
        $price = $result->fetch_assoc()['config_value'] ?? '19900';
        
        return json_encode([
            'success' => true,
            'price' => $price,
            'currency' => 'COP'
        ]);
    }
}
?>