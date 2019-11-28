USE [distribution]
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE PROCEDURE [dbo].[usp_ReplicationMonitor]
/* 
Purpose: This procedure can be used for regular checking of replication status on distribution server. It is using builtin stored procedure sp_replmonitorhelpsubscription.
	Returning table of subscriptions that are not working properly based on agreed rules. Use output parameter to react accordingly in workflow where called. 
	
Author:	Tomas Rybnicky trybnicky@inwk.com
Date of last update: 
	v1.0 - 27.11.2019 - final state where all functionality tested and ready for production
List of previous revisions:
	v0.1 - 27.11.2019 - initial release of this stored procedure
	
Execution example:
	DECLARE @RiseAlert BIT	
	EXEC [distribution].[dbo].[usp_ReplicationMonitor] @RiseAlert OUTPUT	
	SELECT @RiseAlert
*/
@p_SuppressResults	BIT = 0,		-- set to "1" to prevent returning resultset
@p_RiseAlert		BIT = 0 OUTPUT	-- output parameter indicating problem
AS
BEGIN
	SET NOCOUNT ON	

	-- decision if alert to be risen
	SELECT @p_RiseAlert = COUNT(*) FROM [distribution].[dbo].[v_ReplicationMonitorData]
	WHERE ReplicationWarning <> 0 -- some threshold is broken
		OR ReplicationStatus NOT IN (1, 3, 4) -- 1 = Started, 3 = In progress, 4 = Idle 

	-- result set for reporting
	IF @p_RiseAlert <> 0 AND @p_SuppressResults = 0
	BEGIN
		SELECT
			PublisherServer,
			PublisherDatabase,
			SubscriberServer,
			SubscriberDatabase,
			CASE ReplicationType
				WHEN 0 THEN 'Transactional'
				WHEN 1 THEN 'Snapshot'
				WHEN 2 THEN 'Merge'
			END AS ReplicationType,
			CASE ReplicationStatus
				WHEN 6 THEN 'Failed'
				WHEN 5 THEN 'Retrying'
				WHEN 4 THEN 'Idle'
				WHEN 3 THEN 'In progress'
				WHEN 2 THEN 'Stopped'		
				WHEN 1 THEN 'Started'			
			END AS ReplicationStatus,
			ReplicationLatency,
			LastSync AS LastSync
		FROM v_ReplicationMonitorData
		WHERE ReplicationWarning <> 0 -- some threshold is broken
			OR ReplicationStatus NOT IN (1, 3, 4) -- 1 = Started, 3 = In progress, 4 = Idle 
	END
END

GO


