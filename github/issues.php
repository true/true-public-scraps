#!/usr/bin/php
<?php
  // issues.php
  //
  // Script to parse all the issues from json to CSV.
  // This script needs the imput from getAllIssues.sh to work
  // properly.
  //
  // Author   : L. Lakkas
  // Version  : 0.01
  // Copyright: L. Lakkas @ TrueServer.nl B.V.
  //

  if(! defined('STDIN') ) {
    echo("Not Running from CLI");
    exit;
  }

  if (isset($argv[1])) {
    $filename = $argv[1];
  } else {
    $filename = "/tmp/dumpIssues.json";
  }

  if (file_exists("$filename")) {
    $file = fopen("$filename", 'r');
    $content = fread($file, filesize("$filename"));
    $issues = json_decode($content);

    // I retrieve milestone, issue number, state, title, description, github URL and last update
    // echo "Milestone;Number;State;Title;Body;Labels;URL;LastUpdate;\n";
    echo "Issues\n";
    echo "Milestone;Number;Title;Labels;LastUpdate;State;\n";
    foreach ($issues as $i) {
	echo "\"".$i->milestone->title . "\";";
	echo "\"".$i->number . "\";";
	echo "\"".$i->title . "\";";
	echo "\"";

	$resultstr = array();
	foreach ($i->labels as $result) {
		// Gather statistics per label
		if (isset($lblStats[$result->name])) {
			$lblStats[$result->name]++;
		} else {
			$lblStats[$result->name] = 1;
		}
		$resultstr[] = $result->name;

	}
	$result = implode(",",$resultstr);
	echo $result."\";";

	echo "\"". str_replace("Z", "", str_replace("T", " ", $i->updated_at)) . "\";";
	echo "\"".$i->state . "\";";
	echo "\n";
	// Would you like to output everything?
	// echo $i->milestone->title.";".$i->number.";".$i->state.";".$i->title.";".$i->body."\n\r";
    }
  } else {
    echo "File '$filename' does not exist. Make sure you run the 'getAllIssues.sh' Bash script!\n";
    exit;
  }

  // Sort array based on value to show the label with the most issues on top
  arsort($lblStats);

  echo "\n\nStatistics";
  echo "\nLabel;#issues";
  foreach ( $lblStats as $label => $count ) {
    echo "\n\"$label\";\"$count\"";
  }
  echo "\n";

/*
Output example:

    [state] => open
    [closed_at] => 
    [created_at] => 2012-04-25T15:10:46Z
    [comments] => 1
    [assignee] => 
    [body] => This is the body of the issue
    [title] => Subject of the issue
    [html_url] => https://github.com/org/repo/issues/1337
    [number] => 1337
    [updated_at] => 2012-06-11T12:48:25Z
    [milestone] => 
*/

?>
