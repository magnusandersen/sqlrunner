# Parts Town SQL Runner
This simple application works as a substitute for multiple SQL agent jobs.  It allows you to store T-SQL in a column and schedule it to execute periodically.  There is a master SQL Agent job that calls the SQL Runner stored procedure.  We here at Parts Town, have it set up to execute every 60 seconds between 5 AM and 11 PM.

## t_sql_runner table
Valid values on specific columns:
- enabled: 1 or 0
- sql: This value has to be valid T-SQL for the task to execute correctly
- daysofweek: 1 through 7.  1 = Monday and 7 = Sunday
- start_time: 24h clock start time.  It has to be in format `hh:mm`
- end_time: 24h clock end time. It has to be in format `hh:mm`
- freq_min: Set how often you want the task to repeat within the start_time and end_time.

## t_email_recipient_list
This table is used to set who receives an email if usp_sql_runner has a task that fails.
Valid values on specific columns:
- source: Needs to say `usp_sql_runner`
- recipient_list: comma-separated list of valid email addresses.  This list is the `TO` email section
- copy_recipient_list: comma-separated list of valid email addresses.  This list is the `CC` email section

## Example task creation
```sql
/* SQL Runner Script to monitor imports and send alerts */
USE AAD;
GO
IF EXISTS (SELECT 1 FROM dbo.t_pt_sql_runner tpsr WHERE tpsr.name = 'Outbound Delivery Flow')
BEGIN
	DELETE dbo.t_pt_sql_runner WHERE name = 'Outbound Delivery Flow';
END
GO
INSERT INTO dbo.t_pt_sql_runner 
	( name, enabled, sql, daysofweek, start_time
    , end_time, freq_minutes, ins_dt)
VALUES ('Outbound Delivery Flow', 1
      , '
      /* Constants */
DECLARE @cEmailTo NVARCHAR(MAX) = ''email@example.com'';
DECLARE @cMinutesBack INT = 10;
DECLARE @cOrderThreshold INT = 20;
DECLARE @cWebOrderThreshold INT = 5;

/* Variables */
DECLARE @orderCount INT;
DECLARE @webOrderCount INT;
DECLARE @emailBody NVARCHAR(MAX);
DECLARE @emailSubject NVARCHAR(255); 

/* Capture order count based on @cMinutesBack */
SELECT @orderCount = COUNT(1)
FROM dbo.t_al_host_order_master al_orm
WHERE al_orm.record_create_date > DATEADD(MINUTE,-@cMinutesBack,GETDATE());

/* If @orderCount does not exceed @cThreshold send email alert */
IF @orderCount <= @cOrderThreshold
BEGIN
    /* Set email subject */
    SET @emailSubject = ''Alert!! Slow Outbound Delivery Flow: '' 
                      + CONVERT(NVARCHAR,@orderCount) 
                      + '' in Last ''
                      + CONVERT(NVARCHAR,@cMinutesBack) + '' Minutes ''
                      + ''(PRODUCTION)'';

    /* Set email body */
    SET @emailBody = ''<b>Outbound delivery flow appears to be slower than usual.<br>'' 
                   + ''Check with Boomi, SAP, Hybris ''
                   + ''teams to see if there is an issue slowing their transmission to HighJump.<br><br>''
                   + ''Helpful queries:</b><br><br>''
                   + ''/* Query returns import records grouped in 10m increments. */<br>''
                   + ''/* Use this to see trends for orders dropped to HJ */<br>''
                   + ''SELECT CONVERT(VARCHAR(15), hom.record_create_date, 120), COUNT(*)<br>''
                   + ''FROM dbo.t_al_host_order_master hom<br>''
                   + ''GROUP BY CONVERT(VARCHAR(15), hom.record_create_date, 120)<br>''
                   + ''ORDER BY CONVERT(VARCHAR(15), hom.record_create_date, 120) DESC;<br><br>''
                   + ''/* The following queries look at our host tables for order entries for today. */<br>''
                   + ''/* Look at this if the trend from host is healthy. */<br>''
                   + ''SELECT *<br>''
                   + ''FROM dbo.t_al_sap_sql_import_queue imp<br>''
                   + ''WHERE imp.import_type = ''''ORDER''''<br>''
                   + ''  AND imp.date_inserted > CONVERT(DATE,GETDATE())<br>''
                   + ''ORDER BY imp.import_id DESC<br><br>''
                   + ''SELECT *<br>''
                   + ''FROM dbo.t_al_host_order_master al_orm<br>''
                   + ''WHERE al_orm.host_group_id IN (SELECT imp.host_group_id<br>''
                   + ''                               FROM dbo.t_al_sap_sql_import_queue imp<br>''
                   + ''                               WHERE imp.import_type = ''''ORDER''''<br>''
                   + ''                                 AND imp.date_inserted > CONVERT(DATE,GETDATE()))<br>''
                   + ''ORDER BY al_orm.host_order_master_id DESC<br><br>''
                   + ''SELECT * <br>''
                   + ''FROM dbo.t_al_host_order_detail al_ord<br>''
                   + ''WHERE al_ord.host_group_id IN (SELECT imp.host_group_id<br>''
                   + ''                               FROM dbo.t_al_sap_sql_import_queue imp<br>''
                   + ''                               WHERE imp.import_type = ''''ORDER''''<br>''
                   + ''                                 AND imp.date_inserted > CONVERT(DATE,GETDATE()))<br>''
                   + ''ORDER BY al_ord.host_order_detail_id DESC'';


    /* Send email */
   	EXEC msdb.dbo.sp_send_dbmail 
 	     @recipients = @cEmailTo
	   , @body_format = ''HTML''
	   , @body = @emailBody
	   , @subject = @emailSubject; 

END
ELSE
BEGIN 
    /* Get count of Web Orders based on @cMinutesBack */
    SELECT @webOrderCount = COUNT(1)
    FROM dbo.t_al_host_order_master al_orm
    WHERE al_orm.pt_web_order_number IS NOT NULL
      AND al_orm.record_create_date > DATEADD(MINUTE,-@cMinutesBack,GETDATE());

    IF @webOrderCount < @cWebOrderThreshold
    BEGIN
        /* Set email subject */
        SET @emailSubject = ''Alert!! Slow Web Order Delivery Flow: '' 
                          + CONVERT(NVARCHAR,@orderCount) 
                          + '' in Last ''
                          + CONVERT(NVARCHAR,@cMinutesBack) + '' Minutes ''
                          + ''(PRODUCTION)'';

        /* Set email body */
        SET @emailBody = ''<b>Web order delivery flow appears to be slower than usual.<br>'' 
                   + ''Check with Boomi, SAP, Hybris ''
                   + ''teams to see if there is an issue slowing their transmission to HighJump.<br><br>''
                   + ''Helpful queries:</b><br><br>''
                   + ''/* Query returns import records grouped in 10m increments. */<br>''
                   + ''/* Use this to see trends for web orders dropped to HJ */<br>''
                   + ''SELECT CONVERT(VARCHAR(15), hom.record_create_date, 120), COUNT(*)<br>''
                   + ''FROM dbo.t_al_host_order_master hom<br>''
                   + ''WHERE hom.pt_web_order_number IS NOT NULL <br>''
                   + ''GROUP BY CONVERT(VARCHAR(15), hom.record_create_date, 120)<br>''
                   + ''ORDER BY CONVERT(VARCHAR(15), hom.record_create_date, 120) DESC'';

    /* Send email */
   	EXEC msdb.dbo.sp_send_dbmail 
 	     @recipients = @cEmailTo
	   , @body_format = ''HTML''
	   , @body = @emailBody
	   , @subject = @emailSubject;
       
   END; 
END;'
      , '12345'      -- daysofweek - varchar(7)
      , '08:00'      -- start_time - varchar(5)
      , '20:00'      -- end_time - varchar(5)
      , 10       -- freq_minutes - int
      , DEFAULT -- ins_dt - datetime
      )
```
