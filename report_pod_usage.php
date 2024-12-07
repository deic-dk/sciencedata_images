<?php

OCP\App::checkAppEnabled('files_accounting');
OCP\App::checkAppEnabled('files_sharding');
OCP\App::checkAppEnabled('user_pods');

if(!OCA\FilesSharding\Lib::checkIP()){
	http_response_code(401);
	exit;
}

$user = $_REQUEST['user'];
$node_name = $_REQUEST['node_name'];
$node_ip = $_REQUEST['node_ip'];
$pod_name = $_REQUEST['pod_name'];
$pod_ip = $_REQUEST['pod_ip'];
$start_time = $_REQUEST['start_time'];
$end_time = $_REQUEST['end_time'];
$running_seconds = $_REQUEST['running_seconds'];
$cycle_day = $_REQUEST['cycle_day'];

$year=$_REQUEST['year'];
// This is the current month, i.e. usage will cover days in this month and the previous
$month=$_REQUEST['month'];
$day=$_REQUEST['day'];
$timestamp = time();

// Write file files_accounting/pods/year_month_pod_id.txt
#USER NODE_NAME NODE_IP POD_NAME POD_IP START_TIME END_TIME RUNNING_SECONDS TIMESTAMP CYCLE_DAY


$dirPath = \OCA\Files_Accounting\Storage_Lib::getPodsUsageDir($user);
if(!file_exists($dirPath)){
	mkdir($dirPath, 0777, false);
}
$filePath = $dirPath . "podsusage_" . $year . "_" . $month .".txt";

$data = "$user $node_name $node_ip $pod_name $pod_ip $start_time $end_time $running_seconds $timestamp $cycle_day";

for($i=0; $i<3; ++$i){
	$ret = file_put_contents($filePath, $data, FILE_APPEND | LOCK_EX);
	if($ret){
		break;
	}
	sleep(1);
}

OCP\JSON::encodedPrint($ret);


