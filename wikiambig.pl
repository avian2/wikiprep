###############################################################################
#
# wikiambig.pl - Find disambiguation pages in Wikipedia XML dumps
# Copyright (C) 2007 Zemanta
# Copyright (C) 2007 Evgeniy Gabril
# The author can be contacted by electronic mail at tomaz.solc@tablix.org
#
#    This program is free software; you can redistribute it and/or modify
#    it under the terms of the GNU General Public License as published by
#    the Free Software Foundation; either version 2 of the License, or
#    (at your option) any later version.
#
#    This program is distributed in the hope that it will be useful,
#    but WITHOUT ANY WARRANTY; without even the implied warranty of
#    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#    GNU General Public License for more details.
#
#    You should have received a copy of the GNU General Public License
#    along with this program; if not, write to the Free Software
#    Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA,
#    or see <http://www.gnu.org/licenses/> and
#    <http://www.fsf.org/licensing/licenses/info/GPLv2.html>
#
###############################################################################


use strict;
use warnings;

use File::Basename;
use Getopt::Long;
use Time::localtime;
use Parse::MediaWikiDump;

my $licenseFile = "COPYING";
my $version = "2.02";

if (@ARGV < 1) {
  &printUsage();
  exit 0;
}

my $file;
my $showLicense = 0;
my $showVersion = 0;

GetOptions('f=s' => \$file,
           'license' => \$showLicense,
           'version' => \$showVersion);

if ($showLicense) {
  if (-e $licenseFile) {
    print "See file $licenseFile for more details.\n"
  } else {
    print "Please see <http://www.gnu.org/licenses/> and <http://www.fsf.org/licensing/licenses/info/GPLv2.html>\n";
  }
  exit 0;
}
if ($showVersion) {
  print "Wikiprep version $version\n";
  exit 0;
}
if (!defined($file)) {
  &printUsage();
  exit 0;
}
if (! -e $file) {
  die "Input file '$file' cannot be opened for reading\n";
}


##### Global variables #####

my ($fileBasename, $filePath, $fileSuffix) = fileparse($file, ".xml");
my $disambigPagesFile = "$filePath/$fileBasename.disambig";

# Needed for benchmarking and ETA calculation
my $totalPageCount = 0;
my $totalByteCount = 0;

open(DISAMBIGF, "> $disambigPagesFile") or die "Cannot open $disambigPagesFile";

binmode(DISAMBIGF, ':utf8');

print DISAMBIGF  "# Line format: <Disambig page id>\n\n";

print "Counting pages...\n";

&prescan();

&transform();

close(DISAMBIGF);

# Count pages
sub prescan() {
  # re-open the input XML file
  my $pages = Parse::MediaWikiDump::Pages->new($file);

  my $counter = 0;
  
  my $page;
  while (defined($page = $pages->page)) {
    my $id = $page->id;

    $counter++;

    $totalPageCount++;
    $totalByteCount+=length(${$page->text});

    if ($counter % 1000 == 0) {
      print "At page id=$id\n";
    }

  }

  print "Total $totalPageCount pages ($totalByteCount bytes)\n";
}

sub transform() {
  # re-open the input XML file
  my $pages = Parse::MediaWikiDump::Pages->new($file);

  my $processedPageCount = 0;
  my $processedByteCount = 0;

  my $startTime = time-1;

  my $page;
  while (defined($page = $pages->page)) {
    my $id = $page->id;

    $processedPageCount++;
    $processedByteCount+=length(${$page->text});

    my $title = $page->title;
    my $text = ${$page->text};

    if ( $title =~ /({{disambiguation}})|
	                  ({{disambig}})|
            		    ({{dab}})|
                    ({{hndis}})|
                    ({{geodis}})|
                    ({{schooldis}})|
                    ({{hospitaldis}})|
                    ({{mathdab}})/i ) {
      &markDisambig($id);
    } elsif ( $title =~ /\(disambiguation\)/ ) {
      &markDisambig($id);
    }

    my $nowTime = time;

    my $bytesPerSecond = $processedByteCount/($nowTime-$startTime);
    my $percentDone = 100.0*$processedByteCount/$totalByteCount;
    my $secondsLeft = ($totalByteCount-$processedByteCount)/$bytesPerSecond;

    my $hoursLeft = $secondsLeft/3600;

    printf "At %.1f%% (%.0f bytes/s) ETA %.1f hours\n", $percentDone, $bytesPerSecond, $hoursLeft;
  }
}

sub markDisambig(\$) {
	my ($refToid) = @_;

	print DISAMBIGF "$$refToid\n";
}
