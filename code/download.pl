#!/usr/bin/perl -w

=head1 NAME

download.pl - Download and build a new 'itis-dwca' file.

=head1 SYNOPSIS

    PATH_DWCA_HUNTER=~/path/to/dwca-hunt.rb perl download.pl

This script mostly uses environmental variables to link
bits. 

=cut

use 5.0100;

use strict;
use warnings;

use File::Copy;
use File::Copy::Recursive qw(dircopy);
use Archive::Tar;
use Cwd;
use Digest::SHA;
use File::Path qw(remove_tree);
use POSIX qw(strftime);

my $dwca_hunt = find_executable("dwca-hunt-itis.rb", "PATH_DWCA_HUNTER");
my $dwch_stdout;

open(my $fh, '-|', $dwca_hunt)
    or die "Cannot spawn $dwca_hunt: $!";

while(<$fh>) {
    chomp;

    $dwch_stdout .= $_;
    # say STDERR "DWCH: $_";
}

close($fh);

die "Downloading didn't start: $dwch_stdout" unless($dwch_stdout =~ /Starting download of/);
die "Download didn't finish: $dwch_stdout" unless($dwch_stdout =~ /Download finished/);
die "DarwinCore Archive file was not created: $dwch_stdout" unless($dwch_stdout =~ /DarwinCore Archive file is created/);
die "dwca.tar.gz not created into /tmp/dwca_hunter/itis as expected; maybe dwca_hunter has changed?" unless (-e '/tmp/dwca_hunter/itis/dwca.tar.gz');
die "itis not extracted into /tmp/dwca_hunter/itis/itis as expected; maybe dwca_hunter has changed?" unless (-e '/tmp/dwca_hunter/itis/itis');

my $itis_dir = '/tmp/dwca_hunter/itis/itis';
my $dwca_file = '/tmp/dwca_hunter/itis/dwca.tar.gz';

# Figure out which version we used.
opendir(my $itis_dir_file, $itis_dir) or die "Could not open ITIS directory: $!";
my @files = grep { /^version_itisMySQL.*$/ } readdir($itis_dir_file);
my $version_file = $files[0];
closedir($itis_dir_file);

die "No version file generated -- I don't know what version I've working with!" unless defined $version_file;

my $ITISDWCA_PATH = "..";

# Should we bother processing this?
# TODO: is this useful?
if(0) {
    my $sha_latest = Digest::SHA->new(256);
    $sha_latest->addfile("$ITISDWCA_PATH/latest/dwca.tar.gz");

    my $sha_new = Digest::SHA->new(256);
    $sha_new->addfile($dwca_file);

    if($sha_latest->hexdigest eq $sha_new->hexdigest) {
        say "No need to replace 'latest'; the new dwca.tar.gz file is identical to the 'latest'.";
    }

}

# Read the version string.
die "Unable to parse version: $version_file" unless ($version_file =~ /^version_itisMySQL(\d{2})(\d{2})(\d{2})$/);
my $month = $1;
my $day = $2;
my $year = $3;

# Find the directory where we should move this.
my $base_path = "$ITISDWCA_PATH/itis-$month$day$year";
my $new_path = $base_path;

my $count = 1;
while(-e $new_path) {
    $new_path = sprintf("$base_path-%02d", $count);
    $count++;

    die "100 copies of $base_path already exist!" if($count >= 99);
}

# Create and unzip.
mkdir($new_path);
copy($dwca_file, $new_path);

$dwca_file = "$new_path/dwca.tar.gz";
die "Copy failed!" unless(-e $dwca_file);

my $cwd = getcwd;
chdir($new_path);
@files = Archive::Tar->extract_archive($dwca_file, 1);
chdir($cwd);

say "Extraction done: dwca.tar.gz, " . join(', ', @files) . " files created in directory $new_path.";

# Create version.txt.
my @months = ('January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December');
my $month_text = $months[$month - 1];
my $year_text = $year + 2000;

my $database_date = "$month_text $day, $year_text";
my $today = POSIX::strftime("%B %d, %Y", localtime);

open(my $fh_version, ">", "$new_path/version.txt") or die ("Could not open $new_path/version.txt: $!");

print $fh_version <<VERSION_TXT;
$database_date
$version_file
Extracted from $version_file on $today
VERSION_TXT

close($fh_version);

say "Created version.txt.";

# Replace 'latest'.
if(-e "$ITISDWCA_PATH/latest") {
    move("$ITISDWCA_PATH/latest", "$ITISDWCA_PATH/latest_tbd") or die "Could not move latest out of the way: $!";
}
dircopy($new_path, "$ITISDWCA_PATH/latest") or die "Could not copy directory: $!";
if(-e "$ITISDWCA_PATH/latest_tbd") {
    remove_tree("$ITISDWCA_PATH/latest_tbd") or die "Could not recursively delete the old latest: $!";
}

say "Latest replaced.";

# Rewrite index.html with the latest date.
open(my $fh_index_template, "<", "index.html.template") or die "Could not open index.html.template: $!";
open(my $fh_index, ">", "$ITISDWCA_PATH/index.html") or die "Could not open index.html: $!";

while(<$fh_index_template>) {

    s/<insert:creation_date>/$today/g;
    s/<insert:database_date>/$database_date/g;

    print $fh_index $_;
}

close($fh_index_template);
close($fh_index);

=head1 METHODS

=head2 find_executable

Looks for an executable.

=cut

sub find_executable {
    my ($filename, $env_var) = @_;

    # Check if the file is in the present directory.
    return "./$filename" if(-e "./$filename");

    # Check with the environmental variable.
    if(exists $ENV{$env_var}) {
        my $filepath = $ENV{$env_var} . "/$filename";
        return $filepath if(-e $filepath);

        # Perhaps the filename is already part of the path?
        return $ENV{$env_var} if(
            ($ENV{$env_var} =~ /^.*[\\\/]$filename$/) 
            and (-e $ENV{$env_var})
        );
    } else {
        $ENV{$env_var} = "";
    }

    # Die.
    die "Could not find executable: $filename (environment variable $env_var is '" . $ENV{$env_var} ."')";
}

1;
