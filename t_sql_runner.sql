USE [AAD]
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
/* 
This table is used by usp_pt_sql_runner.
*/
CREATE TABLE [dbo].[t_sql_runner](
	[unique_id] [INT] IDENTITY(1,1) NOT NULL,
	[name] [VARCHAR](50) NOT NULL,
	[enabled] [INT] NOT NULL,
	[sql] [VARCHAR](MAX) NOT NULL,
	[daysofweek] [VARCHAR](7) NOT NULL,
	[start_time] [VARCHAR](5) NOT NULL,
	[end_time] [VARCHAR](5) NOT NULL,
	[freq_minutes] [INT] NOT NULL,
	[ins_dt] [DATETIME] NOT NULL DEFAULT (GETDATE()),
	[last_run_dt] [DATETIME] NULL,
	[error_message][VARCHAR](250) NULL
) ON [PRIMARY] TEXTIMAGE_ON [PRIMARY]
GO
GRANT SELECT, INSERT, UPDATE, DELETE ON t_sql_runner TO WA_USER
GO
GRANT SELECT, INSERT, UPDATE, DELETE ON t_sql_runner TO AAD_USER
GO
