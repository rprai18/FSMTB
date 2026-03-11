/**
 * Helper class to update Account records without sharing restrictions
 * This is safe because we verify user access in the calling class before invoking this
 */
public without sharing class AccountUpdateHelper {
    
    /**
     * Update an Account record
     * This method bypasses sharing rules but should only be called after
     * verifying the user has permission to update the Account
     * 
     * @param accountToUpdate The Account record to update
     * @return Database.SaveResult with the update result
     */
    public static Database.SaveResult updateAccount(Account accountToUpdate) {
        return Database.update(accountToUpdate, false);
    }
    
    /**
     * Query an Account by Id without sharing restrictions
     * Used to retrieve Account data that might be restricted by sharing rules
     * 
     * @param accountId The Id of the Account to query
     * @return The Account record, or null if not found
     */
    public static Account getAccountById(Id accountId) {
        List<Account> accounts = [
            SELECT Id, Name, Email__c, BillingStreet, BillingCity, BillingStateCode, 
                   BillingPostalCode, Phone, Fax, Website
            FROM Account
            WHERE Id = :accountId
            LIMIT 1
        ];
        return accounts.isEmpty() ? null : accounts[0];
    }
    
    /**
     * Update Orders without sharing restrictions
     * Used when updating Order records that reference Accounts
     * 
     * @param orders List of Order records to update
     * @return Database.SaveResult array
     */
    public static List<Database.SaveResult> updateOrders(List<Order> orders) {
        return Database.update(orders, false);
    }
    
    /**
     * Query Orders without sharing restrictions
     * Used to retrieve Order records that might be restricted by sharing rules
     * 
     * @param orderIds List of Order IDs to query
     * @param accountId The Account ID to filter by (can be null)
     * @param ownerId The Owner ID to filter by
     * @return List of Order records with OrderItems
     */
    public static List<Order> getOrdersByIds(List<Id> orderIds, Id accountId, Id ownerId) {
        if (accountId != null) {
            return [
                SELECT Id, TotalAmount, AccountId, Status, OwnerId, Pricebook2Id,
                       (SELECT Id, PricebookEntryId, Product2Id, Product2.ProductCode, 
                               Membership__c, Order.Lead__c, Course__c, 
                               UnitPrice, Course_Name__c, Course__r.Name 
                        FROM OrderItems),
                       Lead__c
                FROM Order
                WHERE Id IN :orderIds 
                AND Status = 'Draft' 
                AND AccountId = :accountId 
                AND OwnerId = :ownerId
            ];
        } else {
            // Query without AccountId filter
            return [
                SELECT Id, TotalAmount, AccountId, Status, OwnerId, Pricebook2Id,
                       (SELECT Id, PricebookEntryId, Product2Id, Product2.ProductCode, 
                               Membership__c, Order.Lead__c, Course__c, 
                               UnitPrice, Course_Name__c, Course__r.Name 
                        FROM OrderItems),
                       Lead__c
                FROM Order
                WHERE Id IN :orderIds 
                AND Status = 'Draft' 
                AND OwnerId = :ownerId
            ];
        }
    }
    
    /**
     * Process orders using the LWC-specific CommunityOrderProcessorLWC without sharing restrictions
     * This allows Order processing to work even if sharing rules restrict Account access.
     *
     * NOTE: We intentionally call CommunityOrderProcessorLWC.processOrders (not the legacy CommunityOrderProcessor)
     * because the LWC version contains the updated 4-parameter signature and logic for the new payment flow.
     *
     * @param accountId The Account ID (preserved from registration)
     * @param contactId The Contact ID (preserved from registration, for User creation)
     * @param orders List of Order records
     * @param transactionId The payment transaction ID
     * @return PageReference for redirect
     */
    public static PageReference processOrdersWithoutSharing(Id accountId, Id contactId, List<Order> orders, String transactionId) {
        return CommunityOrderProcessorLWC.processOrders(accountId, contactId, orders, transactionId);
    }
}

