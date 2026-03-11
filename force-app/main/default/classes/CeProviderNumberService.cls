/**
 * Generates unique CE Provider Numbers (format CERP-########, 7 digits with leading zeros, starting at 1100).
 * No Custom Setting or Custom Metadata: uses MAX(CE_Provider_Number_Sequence__c) from Account (CE Provider) to get the next number.
 * Requires Account field CE_Provider_Number_Sequence__c (Number) to store the numeric part so we can query MAX.
 */
global with sharing class CeProviderNumberService {
    private static final String PREFIX = 'CERP-';
    private static final Integer DIGITS = 7;
    private static final Integer START_NUMBER = 1100;

    /** Result for trigger: formatted CE Provider Number and the sequence number to store on Account. */
    global class NextCeProviderNumberResult {
        global String ceProviderNumber;
        global Integer sequenceNumber;
    }

    /**
     * Returns the next CE Provider Number and sequence. Uses MAX(CE_Provider_Number_Sequence__c) from Account (CE Provider).
     * Caller must set both CE_Provider_Number__c and CE_Provider_Number_Sequence__c on the Account.
     * Note: Under high concurrency two records could get the same number; add a unique constraint on CE_Provider_Number__c to detect and retry if needed.
     */
    public static NextCeProviderNumberResult getNextNumberAndSequence() {
        Id ceProviderRtId;
        try {
            ceProviderRtId = [SELECT Id FROM RecordType WHERE SObjectType = 'Account' AND DeveloperName = 'CE_Provider' LIMIT 1].Id;
        } catch (QueryException e) {
            return buildResult(START_NUMBER);
        }

        List<AggregateResult> agg = [
            SELECT MAX(CE_Provider_Number_Sequence__c) maxSeq
            FROM Account
            WHERE RecordTypeId = :ceProviderRtId
        ];
        Decimal maxSeq = (agg != null && !agg.isEmpty()) ? (Decimal) agg[0].get('maxSeq') : null;
        Integer nextNum = (maxSeq == null) ? START_NUMBER : maxSeq.intValue() + 1;
        return buildResult(nextNum);
    }

    private static NextCeProviderNumberResult buildResult(Integer sequenceNumber) {
        NextCeProviderNumberResult r = new NextCeProviderNumberResult();
        r.sequenceNumber = sequenceNumber;
        r.ceProviderNumber = PREFIX + formatNumber(sequenceNumber);
        return r;
    }

    private static String formatNumber(Integer num) {
        String numStr = String.valueOf(num);
        while (numStr.length() < DIGITS) {
            numStr = '0' + numStr;
        }
        return numStr;
    }

    /**
     * Returns only the formatted CE Provider Number (e.g. CERP-0001100). Use when you only need the display value.
     * For new Account assignment, use getNextNumberAndSequence() and set both CE_Provider_Number__c and CE_Provider_Number_Sequence__c.
     */
    public static String getNextNumber() {
        NextCeProviderNumberResult r = getNextNumberAndSequence();
        return r.ceProviderNumber;
    }

}
