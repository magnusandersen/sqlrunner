USE AAD;
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO
ALTER PROCEDURE [dbo].[usp_sql_runner]
/*
PURPOSE: This procedure is called by SQL Server Agent Job: PT SQL Runner
         It runs every minute to grab all alerts from t_sql_runner

DATE		    BY				    DESCRIPTION	
10/19/2022	Matt Nephew		CREATED		
*/
AS
BEGIN
    DECLARE
        @v_dtRunDateTime       DATETIME
        ,@v_nRunWeekDay        CHAR(1)
        ,@v_vchRunTime         VARCHAR(5)
        ,@v_nTotalSQLCnt       INT          = 0
        ,@v_nCurrentSQLID      INT          = 0
        ,@v_nCurrentSQLCnt     INT          = 0
        ,@v_vchSQL             NVARCHAR(MAX)
        ,@v_vchErrorMsg        VARCHAR(MAX)
        ,@v_vchName            VARCHAR(50)
        ,@v_vcherrorfirst50    VARCHAR(50)
        ,@v_vcherrorsecond50   VARCHAR(50)
        ,@v_vchEmailMessage    VARCHAR(MAX)
        ,@v_vchEmailRecipients VARCHAR(MAX)
	,@v_vchRaiseErrorTxt	VARCHAR(100);

    SET @v_dtRunDateTime = GETDATE();
    SET @v_nRunWeekDay = DATEPART(WEEKDAY, @v_dtRunDateTime);
    SET @v_vchRunTime = CONVERT(TIME, @v_dtRunDateTime);

    SET NOCOUNT ON;

    IF OBJECT_ID(N'tempdb..#SQLToRun') IS NOT NULL
        DROP TABLE #SQLToRun;

    /* Create a temp table to hold the alerts we need to run */
    CREATE TABLE #SQLToRun
    (
        unique_id INT
    );

    /* Fill the alert temp table with the alerts for this execution of the procedure */
    INSERT INTO #SQLToRun
        (
            unique_id
        )
    SELECT
        tpsr.unique_id
    FROM dbo.t_sql_runner tpsr
    WHERE enabled = 1
          AND tpsr.daysofweek LIKE '%' + @v_nRunWeekDay + '%' /* Only alerts set to run on this day of the week. Alerts can be scheduled for multiple days, so use a like check. (Sunday = 1, Monday = 2, Tuesday = 3, Wednesday = 4, Thursday = 5, Friday = 6, Saturday = 7)  */
          AND @v_vchRunTime
          BETWEEN tpsr.start_time AND tpsr.end_time /* Only alerts set to run at this time */
          AND DATEDIFF(MINUTE, ISNULL(tpsr.last_run_dt, '1900-01-01 00:00:00.000'), GETDATE()) >= tpsr.freq_minutes; /* Only alerts that have not run within the last freq_minues minutes */

    /* If nothing is in the temp table, we have no alerts to run.. Leave */
    SELECT
        @v_nTotalSQLCnt = COUNT(*)
    FROM #SQLToRun tatr;

    SELECT
        @v_vchEmailRecipients = ISNULL(tperl.recipient_list, 'wizards@partstown.com')
    FROM dbo.t_email_recipient_list tperl
    WHERE source = 'usp_sql_runner';

    IF @v_nTotalSQLCnt = 0
    BEGIN
        RAISERROR('No alerts to run', 0, 1) WITH NOWAIT;
        GOTO EXIT_LABEL;
    END;

    WHILE @v_nCurrentSQLCnt < @v_nTotalSQLCnt
    BEGIN
        SET @v_vchErrorMsg = NULL;

        SELECT TOP(1)
               @v_nCurrentSQLID = unique_id
        FROM #SQLToRun tatr
        WHERE tatr.unique_id > @v_nCurrentSQLID
        ORDER BY tatr.unique_id;

        SELECT
            @v_vchSQL = tpsr.sql
            ,@v_vchName = tpsr.name
        FROM dbo.t_sql_runner tpsr
        WHERE tpsr.unique_id = @v_nCurrentSQLID;

		/* Print output so we can see what is processed in job history */
		SET @v_vchRaiseErrorTxt = 'Executing unique_id: ' + CONVERT(varchar, @v_nCurrentSQLID)
		RAISERROR(@v_vchRaiseErrorTxt, 0, 1) WITH NOWAIT

        /* add try catch and add field to table to hold error, if one exists. Also add tran log for failures*/
        BEGIN TRY
            EXEC sp_executesql @v_vchSQL;
        END TRY
        BEGIN CATCH
            SET @v_vchErrorMsg = N'A SQL error occurred in t_pt_sql_runner.unique_id: '
                                 + CONVERT(VARCHAR, @v_nCurrentSQLID) + '. ' + ERROR_MESSAGE();
            SET @v_vcherrorfirst50 = SUBSTRING(@v_vchErrorMsg, 1, 50);
            SET @v_vcherrorsecond50 = SUBSTRING(@v_vchErrorMsg, 51, 50);

            /* Email wizards for error awareness*/
            SET @v_vchEmailMessage = @v_vchErrorMsg;
            SET @v_vchEmailMessage = @v_vchEmailMessage + CHAR(10)
                                     + 'select * from t_pt_sql_runner where unique_id = '''
                                     + CONVERT(VARCHAR, @v_nCurrentSQLID) + '''';
            SELECT
                *
            FROM dbo.t_email_recipient_list tperl;
            EXEC msdb.dbo.sp_send_dbmail
                @recipients = @v_vchEmailRecipients
                ,@body = @v_vchEmailMessage
                ,@importance = 'HIGH'
                ,@subject = 'Failed execution in t_pt_sql_runner';
        END CATCH;

        UPDATE
            dbo.t_sql_runner
        SET
            [last_run_dt] = FORMAT(@v_dtRunDateTime, 'yyyy-MM-dd HH:mm')
            ,[error_message] = LEFT(@v_vchErrorMsg, 250)
        WHERE unique_id = @v_nCurrentSQLID;

        SET @v_nCurrentSQLCnt = @v_nCurrentSQLCnt + 1;
    END;

    --------------------------------------------------------------------------------------------------------------------------------------
    -- Exit label -- Always leave the function from here.
    --------------------------------------------------------------------------------------------------------------------------------------
    EXIT_LABEL:

END;
GO
GRANT EXECUTE ON [dbo].[usp_pt_sql_runner] TO [AAD_USER] AS [dbo];
GO

GRANT EXECUTE ON [dbo].[usp_pt_sql_runner] TO [WA_USER] AS [dbo];
GO
