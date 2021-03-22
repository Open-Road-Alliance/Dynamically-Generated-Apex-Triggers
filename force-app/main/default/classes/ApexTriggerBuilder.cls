public with sharing class ApexTriggerBuilder {

    public class ApexTriggerBuilderRequest {
        @InvocableVariable(required=true)
        public ID recordId; 
    }

    public class ApexTriggerBuilderResult {
        @InvocableVariable
        public String asyncRequestId;
    }

    private class Configuration {
        private String sObjectName;
        private Integer versionNumber;
        private List<Dynamic_Apex_Trigger_Configuration__c> triggerDetails;
        private String fileNamePrefix;
        private String triggerName;
        private String triggerTestName;
        private String sObjectFileName;

        private Configuration() {
            fileNamePrefix = 'DynamicTrigger_';
        }
    }

    @InvocableMethod(label='Dynamic Apex Trigger Builder')
    public static void buildTriggers(List<ApexTriggerBuilderRequest> requests) {

        for (ApexTriggerBuilderRequest request : requests) {
            ID recordId = request.recordId;
            buildTrigger(recordId);
        }
    }

    @future(callout=true)
    public static void buildTrigger(ID recordId) {
        Dynamic_Apex_Trigger_Configuration__c record = recordId == null ? new Dynamic_Apex_Trigger_Configuration__c() : [SELECT SObject_Name__c, API_Version_Number__c, Async_Request_ID__c 
                    FROM Dynamic_Apex_Trigger_Configuration__c
                    WHERE Id =: recordId
                    WITH SECURITY_ENFORCED];
        List<Dynamic_Apex_Trigger_Configuration__c> records = new List<Dynamic_Apex_Trigger_Configuration__c>();
        Configuration config = new Configuration(); 
        config.sObjectName = record.SObject_Name__c;
        config.versionNumber = (Integer) record.API_Version_Number__c;
        config.triggerDetails = [SELECT SObject_Name__c, Field__c, Field_Condition__c, On_Complete_Callback__c 
                    FROM Dynamic_Apex_Trigger_Configuration__c
                    WHERE SObject_Name__c =: config.sObjectName AND Deployed__c = TRUE
                    WITH SECURITY_ENFORCED];
        Boolean isValid = validateTrigger(config);
        ApexTriggerBuilderResult result = new ApexTriggerBuilderResult();

        if (!isValid) {
            System.debug('A valid configuration has not been created for the given object.');

            result.asyncRequestId = null;
        } else {
            config.sObjectFileName = config.sObjectName.replace('__c', '');
            config.triggerName = config.fileNamePrefix + config.sObjectFileName;
            config.triggerTestName = config.triggerName  + 'Test';

            String zipStr = getZippedData(config);
            MetadataService.MetadataPort service = getService();
            MetadataService.DeployOptions deployOptions = getDeployOptions(config);

            result.asyncRequestId = Test.isRunningTest() ? '123' : service.deploy(zipStr, DeployOptions).Id;

            record.Async_Request_ID__c = result.asyncRequestId;

            records.add(record);

            SObjectAccessDecision decision = Security.stripInaccessible(AccessType.UPDATABLE, records);
            
            update decision.getRecords();

        }
        System.debug(result);
    }
    public static MetadataService.DeployResult checkAsyncRequest(String id) {
        MetadataService.MetadataPort service = getService();

        return id == '123' ? null : service.checkDeployStatus(id, true);
    }
    private static String getZippedData(Configuration config) {
        Zippex zip = new Zippex();
        zip.addFile('package.xml', Blob.valueOf(getPackageXml(config)), null);
        zip.addFile('triggers/' + config.triggerName + '.trigger-meta.xml', Blob.valueOf(getTriggerMetadata(config)), null);
        zip.addFile('triggers/' + config.triggerName + '.trigger', Blob.valueOf(getTrigger(config)), null);
        zip.addFile('classes/' + config.triggerTestName + '.cls-meta.xml', Blob.valueOf(getTriggerTestMetadata(config)), null);
        zip.addFile('classes/' + config.triggerTestName + '.cls', Blob.valueOf(getTriggerTest(config)), null);
        Blob zipData = zip.getZipArchive();
        
        return EncodingUtil.base64Encode(zipData);
    }
    private static MetadataService.MetadataPort getService() {
        MetadataService.MetadataPort service = new MetadataService.MetadataPort();
        service.SessionHeader = new MetadataService.SessionHeader_element();
        service.SessionHeader.sessionId = UserInfo.getSessionId();

        return service;
    }
    private static MetadataService.DeployOptions getDeployOptions(Configuration config) {
        MetadataService.DeployOptions deployOptions = new MetadataService.DeployOptions();
        deployOptions.allowMissingFiles = false;
        deployOptions.autoUpdatePackage = false;
        deployOptions.checkOnly = false;
        deployOptions.ignoreWarnings = false;
        deployOptions.performRetrieve = false;
        deployOptions.purgeOnDelete = false;
        deployOptions.rollbackOnError = true;
        deployOptions.testLevel = 'RunSpecifiedTests';
        deployOptions.runTests = new List<String>{config.triggerTestName};
        deployOptions.singlePackage = true;

        return deployOptions;
    }
    private static Boolean validateTrigger(Configuration config) {
        return config.versionNumber != null && config.sObjectName != null && config.triggerDetails.size() > 0;
    }

    private static String getPackageXml(Configuration config) {
		return '<?xml version="1.0" encoding="UTF-8"?>' + 
        '<Package xmlns="http://soap.sforce.com/2006/04/metadata">' + 
            '\t<types>' + 
                '\t\t<members>' + config.triggerName + '</members>' +
                '\t\t<name>ApexTrigger</name>' + 
            '\t</types>' + 
            '\t<types>' + 
                '\t\t<members>' + config.triggerTestName + '</members>' +
                '\t\t<name>ApexClass</name>' + 
            '\t</types>' + 
            '\t<version>' + config.versionNumber + '.0</version>' + 
        '</Package>';		
	}

    private static String getMetadata(String type, Configuration config) {
        return '<?xml version="1.0" encoding="UTF-8"?>' +
        '<' + type + ' xmlns="http://soap.sforce.com/2006/04/metadata">' +
            '\t<apiVersion>' + config.versionNumber + '.0</apiVersion>' + 
            '\t<status>Active</status>' +
        '</' + type + '>';	
    }
    private static String getTriggerMetadata(Configuration config) {
		return getMetadata('ApexTrigger', config);
	}
    private static String getTriggerTestMetadata(Configuration config) {
		return getMetadata('ApexClass', config);
	}

    private static String getTrigger(Configuration config) {
		String trig = 'trigger ' + config.triggerName + ' on ' + config.sObjectName + '(AFTER INSERT) {\n' + 
        '\tList<' + config.sObjectName + '> records = Trigger.new;\n' + 
        '\tif (records.size() > 0) {\n' +
        '\t\t' + config.sObjectName + ' record = records.get(0);\n';

        for (Dynamic_Apex_Trigger_Configuration__c triggerDetail : config.triggerDetails) {
            String callback = triggerDetail.On_Complete_Callback__c.contains(';') ? triggerDetail.On_Complete_Callback__c : triggerDetail.On_Complete_Callback__c + ';';
            trig += '\t\tif (record.' + triggerDetail.Field__c + ' == \'' + triggerDetail.Field_Condition__c + '\') {\n' + 
            '\t\t\t' + callback + '\n' +
            '\t\t}\n';
        }
        trig += '\t}\n}';

        return trig;
	}

    private static String getTriggerTest(Configuration config) {
		String trigTest = '@isTest\n' + 
        'public class ' + config.triggerTestName + ' {\n';

        for (Dynamic_Apex_Trigger_Configuration__c triggerDetail : config.triggerDetails) {
            Integer ix = config.triggerDetails.indexOf(triggerDetail);
            trigTest += '\tpublic static testMethod void test' + ix + '() {\n' +
            '\t\t' + config.sObjectName + ' record = (' + config.sObjectName + ') TestDataFactory.createSObject(\'' + config.sObjectName + '\', ' +
            'new Map<String, Object>{\'' + triggerDetail.Field__c + '\' => \'' + triggerDetail.Field_Condition__c + '\'});\n' + 
            '\t}\n';
        }
        trigTest += '}';

        return trigTest;
	}
}
