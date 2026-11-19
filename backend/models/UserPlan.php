<?php
class UserPlan {
    private $conn;
    
    public function __construct($db) {
        $this->conn = $db;
    }
    
    public function getUserAccess($userId) {
        $query = "SELECT 
                    u.access_level,
                    u.is_early_user,
                    u.unlocked_at,
                    u.trial_ends_at,
                    u.registration_date,
                    uap.unlocked_modules,
                    uap.payment_id
                  FROM usuarios u
                  LEFT JOIN user_access_plans uap ON u.id = uap.user_id 
                    AND uap.id = (
                        SELECT MAX(id) 
                        FROM user_access_plans 
                        WHERE user_id = u.id
                    )
                  WHERE u.id = ?";
        
        $stmt = $this->conn->prepare($query);
        $stmt->bind_param("i", $userId);
        $stmt->execute();
        $result = $stmt->get_result();
        
        return $result->fetch_assoc();
    }
    
    public function canAccessContent($userId, $contentType, $contentId) {
        $userAccess = $this->getUserAccess($userId);
        
        // Early bird y premium tienen acceso total
        if ($userAccess['access_level'] == 'early_bird' || 
            $userAccess['access_level'] == 'premium') {
            return true;
        }
        
        // Usuario free - verificar si el contenido está en unlocked_modules
        if (!empty($userAccess['unlocked_modules'])) {
            $unlocked = json_decode($userAccess['unlocked_modules'], true);
            $contentKey = $contentType . "_" . $contentId;
            
            if (in_array($contentKey, $unlocked)) {
                return true;
            }
        }
        
        // Verificar configuración global
        $query = "SELECT min_plan FROM content_access_levels 
                  WHERE content_type = ? AND content_id = ? AND is_active = 1";
        $stmt = $this->conn->prepare($query);
        $stmt->bind_param("si", $contentType, $contentId);
        $stmt->execute();
        $result = $stmt->get_result();
        
        if ($row = $result->fetch_assoc()) {
            // Mapear niveles de plan
            $planHierarchy = ['free' => 0, 'early_bird' => 1, 'premium' => 2];
            $userPlanLevel = $planHierarchy[$userAccess['access_level']] ?? 0;
            $requiredPlanLevel = $planHierarchy[$row['min_plan']] ?? 0;
            
            return $userPlanLevel >= $requiredPlanLevel;
        }
        
        // Por defecto, denegar acceso
        return false;
    }
    
    public function upgradeToPremium($userId, $paymentData) {
        $this->conn->begin_transaction();
        
        try {
            // 1. Registrar pago
            $query = "INSERT INTO payments 
                      (user_id, payment_method, transaction_id, amount, status, receipt_data)
                      VALUES (?, ?, ?, ?, 'completed', ?)";
            $stmt = $this->conn->prepare($query);
            $stmt->bind_param(
                "issds",
                $userId,
                $paymentData['payment_method'],
                $paymentData['transaction_id'],
                $paymentData['amount'],
                $paymentData['receipt_data']
            );
            $stmt->execute();
            $paymentId = $stmt->insert_id;
            
            // 2. Actualizar usuario
            $query = "UPDATE usuarios 
                      SET access_level = 'premium', 
                          unlocked_at = NOW()
                      WHERE id = ?";
            $stmt = $this->conn->prepare($query);
            $stmt->bind_param("i", $userId);
            $stmt->execute();
            
            // 3. Registrar en historial de planes
            $query = "INSERT INTO user_access_plans 
                      (user_id, plan_type, payment_id)
                      VALUES (?, 'premium', ?)";
            $stmt = $this->conn->prepare($query);
            $stmt->bind_param("ii", $userId, $paymentId);
            $stmt->execute();
            
            $this->conn->commit();
            return ['success' => true, 'payment_id' => $paymentId];
            
        } catch (Exception $e) {
            $this->conn->rollback();
            return ['success' => false, 'error' => $e->getMessage()];
        }
    }
    
    public function checkEarlyUserStatus($userId) {
        // Verificar si el usuario califica como early bird
        $user = $this->getUserAccess($userId);
        
        // Si ya tiene estado, mantenerlo
        if ($user['access_level'] != 'free') {
            return $user['access_level'];
        }
        
        // Verificar límite de early users
        $query = "SELECT config_value FROM system_config 
                  WHERE config_key = 'early_user_limit'";
        $stmt = $this->conn->prepare($query);
        $stmt->execute();
        $result = $stmt->get_result();
        $limit = $result->fetch_assoc()['config_value'] ?? 1000;
        
        // Contar early users actuales
        $query = "SELECT COUNT(*) as count FROM usuarios 
                  WHERE access_level = 'early_bird' OR is_early_user = 1";
        $stmt = $this->conn->prepare($query);
        $stmt->execute();
        $result = $stmt->get_result();
        $current = $result->fetch_assoc()['count'];
        
        // Si aún hay cupo, hacerlo early bird
        if ($current < $limit) {
            $query = "UPDATE usuarios 
                      SET access_level = 'early_bird', 
                          is_early_user = 1,
                          trial_ends_at = DATE_ADD(NOW(), INTERVAL 180 DAY)
                      WHERE id = ?";
            $stmt = $this->conn->prepare($query);
            $stmt->bind_param("i", $userId);
            $stmt->execute();
            
            return 'early_bird';
        }
        
        return 'free';
    }
}
?>