#!/usr/bin/env perl
use warnings;
use strict;
use Getopt::Long;
use Pod::Usage;
use Time::Piece;
use File::Basename;

my $type;
my $data_dir="/home/jxs1984/MCC/data";
my $sheet;
my $genome="hg19";

my $pipeline_home = readpipe("cd `dirname $0`;pwd");
chomp $pipeline_home;
my $work_dir="";
my $dryrun;
my $local;
my $dag;
my $help;

#$pipeline_home = readpipe()
#if (`dirname $0` =~ /^\./){
#	$pipeline_home = `pwd`;	
#}

chomp $pipeline_home;

my $usage = <<__EOUSAGE__;

Usage:

$0 [options]

required options:

  -type|t     <string>  Pipeline type (available options: hic,chipseq,ranseq,dnaseq)
  -workdir|w  <string>  Working directory where all the results will be stored.
  -sheet|s    <string>  Sample sheet in YAML format
  -genome|g   <string>  Genome version (default: $genome)

optional options:  
  -datadir|d  <string>  FASTQ file location (default: $data_dir)
  -dryrun               Dryrun only
  -local                Run snakemake locally
  -dag                  Generate DAG PDF

Example
  
  launch -type hic -workdir /data/khanlab/projects/HiC/pipeline_dev -s /data/khanlab/projects/HiC/pipeline_dev/samplesheet.yaml

For questions or comments, please contact: Hsienchao Chou <chouh\@nih.gov>
  
__EOUSAGE__

GetOptions(
		'dryrun'        =>\$dryrun,
		'local'         =>\$local,
		'dag'           =>\$dag,
		'type|t=s'      =>\$type,
		'datadir|d=s'   =>\$data_dir,
		'workdir|w=s'   =>\$work_dir,
		'genome|g=s'    =>\$genome,
		'sheet|s=s'     =>\$sheet,
		'help|h'        =>\$help,
	  );

if ($help) {
	print "$usage\n";
	exit 0;
}


if (!$type || ($type ne "hic" && $type ne "chipseq" && $type ne "rnaseq" && $type ne "dnaseq")){
	print STDERR "ERROR: must specify '-type'\n";
	print STDERR "\t Possible values are: hic,chipseq,ranseq,dnaseq\n";
	exit;
}
if ($type ne "hic" && $type ne "rnaseq" && $type ne "chipseq") {
	print STDERR "$type not implemented yet";
	exit;
}
if (!$work_dir){
	print STDERR "-workdir|w is required. Location where you would like to write results\n\n";
	exit;
}
if (!$sheet){
	print STDERR "-sheet|s is required. The samplesheet in YAML format\n";
	exit;
}

$work_dir = readpipe("cd $work_dir;pwd");
chomp $work_dir;
$data_dir = readpipe("cd $data_dir;pwd");
chomp $data_dir;
my $now=`echo \$(date +"%Y%m%d_%H%M%S")`;
chomp $now;
my $jobid;
my $sheet_name = basename($sheet, ".yaml");
my $snakefile="$pipeline_home/khanlab_pipeline.smk";
my $snake_command = "snakemake --directory $work_dir --snakefile $snakefile --configfile $sheet --config type=$type pipeline_home=$pipeline_home work_dir=$work_dir data_dir=$data_dir genome=$genome now=$now";
if ($dryrun){
	$snake_command = $snake_command." -p -r --ri --dryrun";
	if ($dag) {
		$snake_command = $snake_command." --dag | dot -Tsvg > dag.$type.svg";
	}	
	my $cmd = "(
		conda activate snakemake_env
		# module load graphviz # conda install graphviz now in same env
		$snake_command
		rm -f $work_dir/pipeline.$type.${sheet_name}.$now.csv
		)";
	print "$cmd\n";
	exec "$cmd";
}
else{
	system("mkdir -p $work_dir/log");
	system("chmod g+rw $work_dir/log");
	$snake_command = $snake_command." --jobname {params.rulename}.{jobid} --nolock  --ri -k -p -r -j 1000 --cores 150 --jobscript $pipeline_home/scripts/jobscript.sh --cluster \"sbatch --export=ALL -o {params.log_dir}/{params.rulename}.%j.o -e {params.log_dir}/{params.rulename}.%j.e {params.batch}\"";
	if ($local) {
	    system("source ~/.bashrc"); # allows activate
        system("conda init bash");
		system("conda activate snakemake_env"); # puts snakemake on the PATH
		system($snake_command);
	} else {
		my $remote_cmd = "#!/usr/bin/env bash
conda init bash;
conda activate snakemake_env;
$snake_command";
        #print "Running\n$remote_cmd\n\n";
		system('echo "$remote_cmd" > run_'.$type.'_job.sh');
		system("");
        $jobid = readpipe("sbatch --export=ALL -J ${type}_pipeline -e $work_dir/log/pipeline.$type.${sheet_name}_${now}.%j.e -o $work_dir/log/pipeline.$type.${sheet_name}_${now}.%j.o --cpus-per-task=1 --mem=8G --time=24:00:00 $snake_command");
	}
}

chomp $jobid;
print "$jobid\t$sheet\t$pipeline_home\t$work_dir/pipeline.$type.${sheet_name}_$now.log\n" if $jobid;
