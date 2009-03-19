#!/usr/bin/perl -w
###############################################################################
# vim:sw=2:tabstop=2:expandtab
#
# wikiprep.pl - Preprocess Wikipedia XML dumps
# Copyright (C) 2007 Evgeniy Gabrilovich
# The author can be contacted by electronic mail at gabr@cs.technion.ac.il
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
# Modifications by Tomaz Solc (tomaz.solc@tablix.org)
#
###############################################################################

use strict;
use warnings;

use File::Basename;
use FileHandle;
use Getopt::Long;
use Time::localtime;
use Parse::MediaWikiDump;
use Regexp::Common;

use FindBin;
use lib "$FindBin::Bin";

use Wikiprep::images qw( convertGalleryToLink convertImagemapToLink parseImageParameters );
use Wikiprep::nowiki qw( replaceTags extractTags );
use Wikiprep::revision qw( writeVersion );
use Wikiprep::languages qw( languageName );
use Wikiprep::templates qw( templateParameterRecursion parseTemplateInvocation );
use Wikiprep::ctemplates qw( splitOnTemplates splitTemplateInvocation );
use Wikiprep::lang qw( getLang );
use Wikiprep::css qw( removeMetadata );
use Wikiprep::logger qw( msg );
use Wikiprep::interwiki qw( parseInterwiki );
use Wikiprep::utils qw( trimWhitespaceBothSides encodeXmlChars getLinkIds removeDuplicatesAndSelf );

use Wikiprep::Output::Legacy;
use Wikiprep::Output::Composite;

my $licenseFile = "COPYING";
my $version = "2.02.tomaz.3";

if (@ARGV < 1) {
  &printUsage();
  exit 0;
}

my $file;
my $showLicense = 0;
my $showVersion = 0;
my $dontExtractUrls = 0;
my $logArgs = "";
my $doCompress = 0;

my $langCode = 'en';
my $outputFormat = "legacy";

GetOptions('f=s' => \$file,
           'license' => \$showLicense,
           'version' => \$showVersion,
           'nourls' => \$dontExtractUrls,
           'log=s' => \$logArgs,
           'compress' => \$doCompress,
           'lang=s' => \$langCode,
           'format=s' => \$outputFormat);

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

my $startTime = time;

my $refToLangDB = &getLang( $langCode );
my %langDB = %$refToLangDB;

##### Global definitions #####

my %numMonthToNumDays = ( 1 => 31, 
                          2 => 29, 
                          3 => 31, 
                          4 => 30, 
                          5 => 31, 
                          6 => 30, 
                          7 => 31, 
                          8 => 31, 
                          9 => 30, 
                          10 => 31, 
                          11 => 30, 
                          12 => 31);

# Create a mapping from month name to the number of days in that month needed by normalizeDates()
my %monthToNumDays;
for my $num ( keys(%numMonthToNumDays) ) {
  $monthToNumDays{ $langDB{'numberToMonth'}->{$num} } = $numMonthToNumDays{$num};
}

my $maxTemplateRecursionLevels = 10;
my $maxTableRecursionLevels = 5;

# We use a different (and faster) way of recursively including templates than MediaWiki. In most
# cases this produces satisfactory results, however certain templates break our parser by resolving
# to meta characters like {{ and |. These templates are used as hacks around escaping issues in 
# Mediawiki and mostly concern wiki table syntax. Since we ignore content in tables we can safely
# ignore these templates.
#
# See http://meta.wikimedia.org/wiki/Template:!
#my %overrideTemplates = ('Template:!' => ' ', 'Template:!!' => ' ', 'Template:!-' => ' ',
#                         'Template:-!' => ' ');

my %overrideTemplates = ();

##### Global variables #####

my %namespaces;

# Replaced global %id2title with %idexists in prescan() to reduce memory footprint.
#my %id2title;
my %title2id;
my %redir;
my %templates;          # template bodies for insertion
my %catHierarchy;       # each category is associated with a list of its immediate descendants
my %statCategories;     # number of pages classified under each category
my %statIncomingLinks;  # number of links incoming to each page

# Counter for IDs assigned to nonexistent pages.
my $localIDCounter = 1;

my ($fileBasename, $filePath, $fileSuffix) = fileparse($file, ".xml", ".xml.gz", ".xml.bz2");
$fileSuffix =~ s/\.gz$|\.bz2//;

my $out;
if( lc($outputFormat) eq 'legacy' ) {
  $out = Wikiprep::Output::Legacy->new("$filePath/$fileBasename", $file, COMPRESS => $doCompress);
} elsif( lc($outputFormat) eq 'composite' ) {
  $out = Wikiprep::Output::Composite->new("$filePath/$fileBasename", $file, COMPRESS => $doCompress);
}

my $logFile = "$filePath/$fileBasename.log";

# Information about dump and wikiprep versions
my $versionFile = "$filePath/$fileBasename.version";

# Needed for benchmarking and ETA calculation
my $totalPageCount = 0;
my $totalByteCount = 0;

&writeVersion($versionFile, $file);
&Wikiprep::logger::init($logFile, $logArgs);

binmode(STDOUT,  ':utf8');
binmode(STDERR,  ':utf8');

&prescan();

$out->lastLocalID($localIDCounter);

my $numTitles = scalar( keys(%title2id) );
print "Loaded $numTitles titles\n";
my $numRedirects = scalar( keys(%redir) );
print "Loaded $numRedirects redirects\n";
my $numTemplates = scalar( keys(%templates) );
print "Loaded $numTemplates templates\n";

&transform();

$out->writeRedirects(\%redir, \%title2id, \%templates);
&writeStatistics();
&writeCategoryHierarchy();

$out->finish();

&Wikiprep::logger::stop();

my $elapsed = time - $startTime;

printf("Processing took %d:%02d:%02d\n", $elapsed/3600, ($elapsed / 60) % 60, $elapsed % 60);

# Hogwarts needs the anchor text file to be sorted in the increading order of target page id.
# The file is originally sorted by source page id (second field in each line).
# We now use stable (-s) numeric (-n) sort on the first field (-k 1,1).
# This way, the resultant file will be sorted on the target page id (first field) as primary key,
# and on the source page id (second field) as secondary key.
# system("sort -s -n -k 1,1 $anchorTextFile > $anchorTextFile.sorted");


##### Subroutines #####

sub normalizeTitle(\$) {
  my ($refToStr) = @_;

  # remove leading whitespace and underscores
  $$refToStr =~ s/^[\s_]+//;
  # remove trailing whitespace and underscores
  $$refToStr =~ s/[\s_]+$//;
  # replace sequences of whitespace and underscore chars with a single space
  $$refToStr =~ s/[\s_]+/ /g;

  if ($$refToStr =~ /^([^:]*):(\s*)(\S(?:.*))/) {
    my $prefix = $1;
    my $optionalWhitespace = $2;
    my $rest = $3;

    my $namespaceCandidate = $prefix;
    &normalizeNamespace(\$namespaceCandidate); # this must be done before the call to 'isKnownNamespace'
    if ( &isKnownNamespace(\$namespaceCandidate) ) {
      # If the prefix designates a known namespace, then it might follow by optional
      # whitespace that should be removed to get the canonical page name
      # (e.g., "Category:  Births" should become "Category:Births").
      $$refToStr = $namespaceCandidate . ":" . ucfirst($rest);
    } else {
      # No namespace, just capitalize first letter.
      # If the part before the colon is not a known namespace, then we must not remove the space
      # after the colon (if any), e.g., "3001: The_Final_Odyssey" != "3001:The_Final_Odyssey".
      # However, to get the canonical page name we must contract multiple spaces into one,
      # because "3001:   The_Final_Odyssey" != "3001: The_Final_Odyssey".
      $$refToStr = ucfirst($prefix) . ":" .
                   (length($optionalWhitespace) > 0 ? " " : "") . $rest;
    }
  } else {
    # no namespace, just capitalize first letter
    $$refToStr = ucfirst($$refToStr);
  }
}

sub normalizeNamespace(\$) {
  my ($refToStr) = @_;

  $$refToStr = ucfirst( lc($$refToStr) );
}

# Checks if the prefix of the page name before the colon is actually one of the
# 16+2+2 namespaces defined in the XML file.
# Assumption: the argument was already normalized using 'normalizeNamespace'
sub isKnownNamespace(\$) {
  my ($refToStr) = @_;

  defined( $namespaces{$$refToStr} );  # return value
}

sub isDisambiguation($) {
  my ($page) = @_;

  my $result = 0;

  my $disambigTemplates = $langDB{'disambigTemplates'};
  my $disambigTitle = $langDB{'disambigTitle'};

  if ( ${$page->text} =~ /\{\{\s*$disambigTemplates\s*(?:\|.*)?\s*\}\}/ix ) {
    $result = 1;
  } elsif ( $page->title =~ /$disambigTitle/ix ) {
    $result = 1;
  }

  return $result;
}

# The correct form to create a redirect is #REDIRECT [[ link ]],
# and function 'Parse::MediaWikiDump::page->redirect' only supports this form.
# However, it seems that Wikipedia can also tolerate a variety of other forms, such as
# REDIRECT|REDIRECTS|REDIRECTED|REDIRECTION, then an optional ":", optional "to" or optional "=".
# Therefore, we use our own function to handle these cases as well.
# If the page is a redirect, the function returns the title of the target page;
# otherwise, it returns 'undef'.
sub isRedirect($) {
  my ($page) = @_;

  # quick check
  return undef if ( ${$page->text} !~ /^#REDIRECT/i );

  if ( ${$page->text} =~ m{^\#REDIRECT         # Redirect must start with "#REDIRECT"
                                               #   (the backslash is needed before "#" here, because
                                               #    "#" has special meaning with /x modifier)
                           (?:S|ED|ION)?       # The word may be in any of these forms,
                                               #   i.e., REDIRECT|REDIRECTS|REDIRECTED|REDIRECTION
                           (?:\s*)             # optional whitespace
                           (?: :|\sTO|=)?      # optional colon, "TO" or "="
                                               #   (in case of "TO", we expect a whitespace before it,
                                               #    so that it's not glued to the preceding word)
                           (?:\s*)             # optional whitespace
                           \[\[([^\]]*)\]\]    # the link itself
                          }ix ) {              # matching is case-insensitive, hence /i
    my $target = $1;

    if ($target =~ /^(.*)\#(?:.*)$/) {
      # The link contains an anchor. Anchors are not allowed in REDIRECT pages, and therefore
      # we adjust the link to point to the page as a whole (that's how Wikipedia works).
      $target = $1;
    }

    return $target;
  }

  # OK, it's probably either a malformed redirect link, or something else
  return undef;
}

sub isNamespaceOkForLocalPages(\$) {
  my ($refToNamespace) = @_;

  # We are only interested in image links, so main namespace is not OK.
  my $result = 0;

  if ($$refToNamespace ne '') {
    if ( &isKnownNamespace($refToNamespace) ) {
      $result = defined( $langDB{'okNamespacesForLocalPages'}->{$$refToNamespace} );
    } else {
      # A simple way to recognize most namespaces that link to translated articles. A better 
      # way would be to store these namespaces in a hash.
      if ( length($$refToNamespace) < 4 ) {
        $result = 0
      }

      # the prefix before ":" in the page title is not a known namespace,
      # therefore, the page belongs to the main namespace and is OK
    }
  }

  $result; # return value
}

sub isNamespaceOkForPrescanning($) {
  my ($page) = @_;

  &isNamespaceOk($page, $langDB{'okNamespacesForPrescanning'});
}

sub isNamespaceOkForTransforming($) {
  my ($page) = @_;

  &isNamespaceOk($page, $langDB{'okNamespacesForTransforming'});
}

sub isNamespaceOk($\%) {
  my ($page, $refToNamespaceHash) = @_;

  my $result = 1;

  # main namespace is OK, so we only check pages that belong to other namespaces

  if ($page->namespace ne '') {
    my $namespace = $page->namespace;
    &normalizeNamespace(\$namespace);
    if ( &isKnownNamespace(\$namespace) ) {
      $result = defined( $$refToNamespaceHash{$namespace} );
    } else {
      # the prefix before ":" in the page title is not a known namespace,
      # therefore, the page belongs to the main namespace and is OK
    }
  }

  $result; # return value
}

sub resolveNamespaceAliases($) {
  my ($targetId) = @_;

  while(my ($key, $value) = each(%{$langDB{'namespaceAliases'}})) {
      $targetId =~ s/^\s*$key:/$value:/mig;
  }

  return $targetId;  
}

sub isTitleOkForLocalPages(\$) {
  my ($refToPageTitle) = @_;

  my $namespaceOk = 0;

  if ($$refToPageTitle =~ /^:.*$/) {
    # Leading colon by itself implies main namespace
    $namespaceOk = 0;

  # Note that there must be at least one non-space character following the namespace specification
  # for the page title to be valid. If there is none, then the link is considered to point to a
  # page in the main namespace.

  } elsif ($$refToPageTitle =~ /^([^:]*):\s*\S/) {
    # colon found but not in the first position - check if it designates a known namespace
    my $prefix = $1;
    &normalizeNamespace(\$prefix);
    $namespaceOk = &isNamespaceOkForLocalPages(\$prefix);
  }

  # The case when the page title does not contain a colon at all also falls here.

  return $namespaceOk
}

sub writeStatistics() {
  my $statCategoriesFile = "$filePath/$fileBasename.stat.categories";
  my $statIncomingLinksFile = "$filePath/$fileBasename.stat.inlinks";

  open(STAT_CATS, "> $statCategoriesFile") or die "Cannot open $statCategoriesFile";
  print STAT_CATS "# Line format: <CategoryId (= page id)>  <Number of pages in this category>\n",
                  "# Here we count the *pages* that belong to this category, i.e., articles AND\n",
                  "# sub-categories of this category (but not the articles in the sub-categories).\n",
                  "\n\n";

  my $cat;
#  foreach $cat ( sort { $statCategories{$b} <=> $statCategories{$a} }
#                 keys(%statCategories) ) {
#    print STAT_CATS "$cat\t$statCategories{$cat}\n";
#  }
  foreach $cat ( keys(%statCategories) ) {
    print STAT_CATS "$cat\t$statCategories{$cat}\n";
  }
  close(STAT_CATS);

  open(STAT_INLINKS, "> $statIncomingLinksFile") or die "Cannot open $statIncomingLinksFile";
  print STAT_INLINKS "# Line format: <Target page id>  <Number of links to it from other pages>\n\n\n";

  my $destination;
#  foreach $destination ( sort { $statIncomingLinks{$b} <=> $statIncomingLinks{$a} }
#                         keys(%statIncomingLinks) ) {
#    print STAT_INLINKS "$destination\t$statIncomingLinks{$destination}\n";
#  }
  foreach $destination ( keys(%statIncomingLinks) ) {
    print STAT_INLINKS "$destination\t$statIncomingLinks{$destination}\n";
  }

  close(STAT_INLINKS);
}

sub writeCategoryHierarchy() {
  my $catHierarchyFile = "$filePath/$fileBasename.cat_hier";

  open(CAT_HIER, "> $catHierarchyFile") or die "Cannot open $catHierarchyFile";
  print CAT_HIER "# Line format: <Category id>  <List of ids of immediate descendants>\n\n\n";

  my $cat;
#  foreach $cat ( sort { $catHierarchy{$a} <=> $catHierarchy{$b} }
#                 keys(%catHierarchy) ) {
#    print CAT_HIER "$cat\t", join(" ", @{$catHierarchy{$cat}}), "\n";
#  }
  foreach $cat ( keys(%catHierarchy) ) {
    print CAT_HIER "$cat\t", join(" ", @{$catHierarchy{$cat}}), "\n";
  }

  close(CAT_HIER);
}

sub loadNamespaces() {
  my ($pages) = @_;

  # load namespaces
  my $refNamespaces = $pages->namespaces;

  # namespace names are case-insensitive, so we force them
  # to canonical form to facilitate future comparisons
  my $ns;
  foreach $ns (@$refNamespaces) {
    my @namespaceData = @$ns;
    my $namespaceId   = $namespaceData[0];
    my $namespaceName = $namespaceData[1];
    &normalizeNamespace(\$namespaceName);
    $namespaces{$namespaceName} = $namespaceId;
  }
}

# build id <-> title mappings and redirection table,
# as well as load templates
sub prescan() {
  # re-open the input XML file
  if ($file =~ /\.gz$/) {
    open(INF, "gzip -dc $file|") or die "Cannot open $file: $!";
  } elsif ($file =~ /\.bz2$/) {
    open(INF, "bzip2 -dc $file|") or die "Cannot open $file: $!";
  } else {
    open(INF, "< $file") or die "Cannot open $file: $!";
  }

  my $pages = Parse::MediaWikiDump::Pages->new(\*INF);

  &loadNamespaces($pages);

  my $counter = 0;
  
  my %idexists;

  my $page;

  while (defined($page = $pages->page)) {
    my $id = $page->id;

    # During prescan set localIDCounter to be greater than any 
    # encountered Wikipedia page ID
    if ($id >= $localIDCounter) {
      $localIDCounter = $id + 1;
    }

    $counter++;

    $totalPageCount++;
    $totalByteCount+=length(${$page->text});

    if ($counter % 1000 == 0) {
      my $timeStr = &getTimeAsString();
      &msg("DEBUG", "[$timeStr] Prescanning page id=$id");
    }

    my $title = $page->title;
    &normalizeTitle(\$title);

    if (length($title) == 0) {
      # This is a defense against pages whose title only contains UTF-8 chars that
      # are reduced to an empty string. Right now I can think of one such case -
      # <C2><A0> which represents the non-breaking space. In this particular case,
      # this page is a redirect to [[Non-nreaking space]], but having in the system
      # a redirect page with an empty title causes numerous problems, so we'll live
      # happier without it.
      &msg("DEBUG", "Skipping page with empty title id=$id");
      next;
    }

    if ( exists($idexists{$id}) ) {
      &msg("WARNING", "Page id=$id already encountered before!");
      next;
    }
    if ( exists($title2id{$title}) ) {
      # A page could have been encountered before with a different spelling.
      # Examples: &nbsp; = <C2><A0> (nonbreakable space), &szlig; = <C3><9F> (German Eszett ligature)
      &msg("WARNING", "Page title='$title' already encountered before!");
      next;
    }

    my $redirect = &isRedirect($page);
    if (defined($redirect)) {
      &normalizeTitle(\$redirect);
      next if (length($redirect) == 0); # again, same precaution here - see comments above
      $redir{$title} = $redirect;

      # nothing more to do for redirect pages
      next;
    }

    if ( ! &isNamespaceOkForPrescanning($page) ) {
      next; # we're only interested in certain namespaces
    }
    # if we get here, then either the page belongs to the main namespace OR
    # it belongs to one of the namespaces we're interested in

    $idexists{$id} = 'x';
    $title2id{$title} = $id;

    my $templateNamespace = $langDB{'templateNamespace'};
    if ($title =~ /^$templateNamespace:/) {
      my $text = ${$page->text};

      $out->newTemplate($id, $title);

      # We're storing template text for future inclusion, therefore,
      # remove all <noinclude> text and keep all <includeonly> text
      # (but eliminate <includeonly> tags per se).
      # However, if <onlyinclude> ... </onlyinclude> parts are present,
      # then only keep them and discard the rest of the template body.
      # This is because using <onlyinclude> on a text fragment is
      # equivalent to enclosing it in <includeonly> tags **AND**
      # enclosing all the rest of the template body in <noinclude> tags.
      # These definitions can easily span several lines, hence the "/s" modifiers.

      # Remove comments (<!-- ... -->) from template text. This is best done as early as possible so
      # that it doesn't slow down the rest of the code.
      
      # Note that comments must be removed before removing other XML tags,
      # because some comments appear inside other tags (e.g. "<span <!-- comment --> class=...>"). 
      
      # Comments can easily span several lines, so we use the "/s" modifier.

      $text =~ s/<!--(?:.*?)-->/ /sg;

      # Enable this to parse Uncyclopedia (<choose> ... </choose> is a
      # MediaWiki extension they use that selects random text - wikiprep
      # creates huge pages if we don't remove it)

      # $text =~ s/<choose[^>]*>(?:.*?)<\/choose[^>]*>/ /sg;

      my $onlyincludeAccumulator;
      while ($text =~ /<onlyinclude>(.*?)<\/onlyinclude>/sg) {
        my $onlyincludeFragment = $1;
        $onlyincludeAccumulator .= "$onlyincludeFragment\n";
      }
      if ( defined($onlyincludeAccumulator)) {
        $text = $onlyincludeAccumulator;
      } else {
        # If there are no <onlyinclude> fragments, simply eliminate
        # <noinclude> fragments and keep <includeonly> ones.
        $text =~ s/<noinclude\s*>.*?<\/noinclude\s*>/\n/sg;

        # In case there are unterminated <noinclude> tags
        $text =~ s/<noinclude\s*>.*$//sg;

        $text =~ s/<includeonly\s*>(.*?)<\/includeonly\s*>/$1/sg;

      }

      $templates{$id} = $text;
    }
  }

  close(INF);
  my $timeStr = &getTimeAsString();
  &msg("DEBUG", "[$timeStr] Prescanning complete - prescanned $counter pages");

  print "Total $totalPageCount pages ($totalByteCount bytes)\n";
  &msg("DEBUG", "Total $totalPageCount pages ($totalByteCount bytes)");
}

sub transform() {
  # re-open the input XML file
  if ($file =~ /\.gz$/) {
    open(INF, "gzip -dc $file|") or die "Cannot open $file: $!";
  } elsif ($file =~ /\.bz2$/) {
    open(INF, "bzip2 -dc $file|") or die "Cannot open $file: $!";
  } else {
    open(INF, "< $file") or die "Cannot open $file: $!";
  }
  my $mwpages = Parse::MediaWikiDump::Pages->new(\*INF);

  my $categoryNamespace = $langDB{'categoryNamespace'};
  my $imageNamespace = $langDB{'imageNamespace'};

  my $processedPageCount = 0;
  my $processedByteCount = 0;

  my $startTime = time - 1;
  my $lastDisplayTime = $startTime;

  my $mwpage;
  while (defined($mwpage = $mwpages->page)) {

    $processedPageCount++;
    $processedByteCount += length(${$mwpage->text});

    my $page = {};

    $page->{startTime} = time;

    if( $page->{startTime} - $lastDisplayTime > 5 ) {

      $lastDisplayTime = $page->{startTime};

      my $bytesPerSecond = $processedByteCount / ( $page->{startTime} - $startTime );
      my $percentDone = 100.0 * $processedByteCount / $totalByteCount;
      my $secondsLeft = ( $totalByteCount - $processedByteCount ) / $bytesPerSecond;

      my $hoursLeft = $secondsLeft/3600;

      printf "At %.1f%% (%.0f bytes/s) ETA %.1f hours \r", $percentDone, $bytesPerSecond, $hoursLeft;
      STDOUT->flush();
    }

    $page->{id} = $mwpage->id;
    $page->{timestamp} = $mwpage->timestamp;

    # next if( $id != 1192748);

    &msg("DEBUG", "Transforming page id=$page->{id}");

    if ( defined( &isRedirect($mwpage) ) ) {
      next; # we've already loaded all redirects in the prescanning phase
    }

    if ( ! &isNamespaceOkForTransforming($mwpage) ) {
      next; # we're only interested in pages from certain namespaces
    }

    my $title = $mwpage->title;
    &normalizeTitle(\$title);

    # see the comment about empty titles in function 'prescan'
    if (length($title) == 0) {
      &msg("DEBUG", "Skipping page with empty title id=$page->{id}");
      next;
    }

    $page->{title} = $title;

    my $text = ${$mwpage->text};

    # text length BEFORE any transformations
    $page->{orgLength} = length($text);

    # Remove comments (<!-- ... -->) from text. This is best done as early as possible so
    # that it doesn't slow down the rest of the code.
      
    # Comments can easily span several lines, so we use the "/s" modifier.

    $text =~ s/<!--(?:.*?)-->/ /sg;

    # Enable this to parse Uncyclopedia (<choose> ... </choose> is a
    # MediaWiki extension they use that selects random text - wikiprep
    # creates huge pages if we don't remove it)

    # $text =~ s/<choose[^>]*>(?:.*?)<\/choose[^>]*>/ /sg;

    # The check for stub must be done BEFORE any further processing,
    # because stubs indicators are templates, and templates are substituted.
    if ( $text =~ m/stub}}/i ) {
      $page->{isStub} = 1;
    } else {
      $page->{isStub} = 0;
    }

    $page->{text} = $text;

    # Parse disambiguation pages before template substitution because disambig
    # indicators are also templates.
    if ( &isDisambiguation($mwpage) ) {
      &msg("DEBUG", "Parsing disambiguation page");

      &parseDisambig($page);

      $page->{isDisambig} = 1;
    } else {
      $page->{isDisambig} = 0;
    }

    $page->{templates} = {};
    $page->{text} = &includeTemplates($page, $page->{text}, 0);

    # This function only examines the contents of '$text', but doesn't change it.
    &identifyRelatedArticles($page);

    # We process categories directly, because '$page->categories' ignores
    # categories inherited from included templates
    &extractCategories($page);

    # Categories are listed at the end of articles, and therefore may mistakenly
    # be added to the list of related articles (which often appear in the last
    # section such as "See also"). To avoid this, we explicitly remove all categories
    # from the list of related links, and only then record the list of related links
    # to the file.
    &removeElements($page->{relatedArticles}, $page->{categories});

    &convertGalleryToLink(\$page->{text}, $refToLangDB);
    &convertImagemapToLink(\$page->{text}, $refToLangDB);

    # Remove <div class="metadata"> ... </div> and similar CSS classes that do not
    # contain usable text for us.
    &removeMetadata(\$page->{text});

    $page->{internalLinks} = [];
    $page->{interwikiLinks} = [];

    &extractWikiLinks(\$page->{text}, $page->{internalLinks}, $page->{interwikiLinks});

    my @internalLinks;
    &getLinkIds(\@internalLinks, $page->{internalLinks});
    &removeDuplicatesAndSelf(\@internalLinks, $page->{id});

    if ( ! $dontExtractUrls ) {
      &extractUrls($page);
    }

    &postprocessText(\$page->{text}, 1, 1);

    # text length AFTER all transformations
    $page->{newLength} = length($page->{text});

    &updateStatistics($page->{categories}, \@internalLinks);

    if ($page->{title} =~ /^$categoryNamespace:/) {
      &updateCategoryHierarchy($page->{id}, $page->{categories});
      $page->{isCategory} = 1;
    } else {
      $page->{isCategory} = 0;
    }

    if ($page->{title} =~ /^$imageNamespace:/) {
      $page->{isImage} = 1;
    } else {
      $page->{isImage} = 0;
    }

    $out->newPage($page);

    my $pageFinishedTime = time;

    &msg("PROFILE", "Transforming page $page->{id} took " . 
                            ( $pageFinishedTime - $page->{startTime} ) .
                            " seconds");
  }
  print "\n";
  close(INF);
}

sub updateStatistics(\@\@) {
  my ($refToCategories, $refToInternalLinks) = @_;

  my $cat;
  foreach $cat (@$refToCategories) {
    $statCategories{$cat}++;
  }

  my $link;
  foreach $link (@$refToInternalLinks) {
    $statIncomingLinks{$link}++;
  }
}

sub updateCategoryHierarchy($\@) {
  # The list of categories passed as a parameter is actually the list of parent categories
  # for the current category
  my ($childId, $refToParentCategories) = @_;

  my $parentCat;
  foreach $parentCat (@$refToParentCategories) {
    if ( exists($catHierarchy{$parentCat}) ) {
      push(@{$catHierarchy{$parentCat}}, $childId);
    } else {
      # create a new array with '$childId' as the only child (for now) of '$parentCat'
      my @arr;
      push(@arr, $childId);
      $catHierarchy{$parentCat} = [ @arr ];
    }
  }
}

# Maps a title into the id, and performs redirection if necessary.
# Assumption: the argument was already normalized using 'normalizeTitle'
sub resolveLink(\$) {
  my ($refToTitle) = @_;

  # safety precaution
  return undef if (length($$refToTitle) == 0);

  my $targetId; # result
  my $targetTitle = $$refToTitle;

  if ( exists($redir{$$refToTitle}) ) { # this link is a redirect
    $targetTitle = $redir{$$refToTitle};

    # check if this is a double redirect
    if ( exists($redir{$targetTitle}) ) {
      my $secondRedirect = $redir{$targetTitle};
      &msg("WARNING", "link '$$refToTitle' caused double redirection and was ignored: '" . 
                      "$$refToTitle' -> '$targetTitle' -> '$secondRedirect'");
      $targetTitle = undef; # double redirects are not allowed and are ignored
    } else {
      &msg("DEBUG", "Link '$$refToTitle' was redirected to '$targetTitle'");
    }
  }

  if ( defined($targetTitle) ) {
    if ( exists($title2id{$targetTitle}) ) {
      $targetId = $title2id{$targetTitle};
    } else {
      # Among links to uninteresting namespaces this also ignores links that point to articles in 
	    # different language Wikipedias. We aren't interested in these links (yet), plus ignoring them 
    	# significantly reduces memory usage.

      if ( ! &isTitleOkForLocalPages(\$targetTitle) ) {
        &msg("DEBUG", "Link '$$refToTitle' was ignored");
        $targetId = undef;
      } else {
      	# Assign a local ID otherwise and add the nonexistent page to %title2id hash
        $targetId = $localIDCounter;
        $localIDCounter++;

        $title2id{$targetTitle}=$targetId;

        $out->newLocalID( $targetId, $targetTitle );

        &msg("DEBUG", "link '$$refToTitle' cannot be matched to an known ID, assigning local ID");
      }  
    }
  } else {
    $targetId = undef;
  }

  $targetId; # return value
}

BEGIN {

my $nowikiRegex = qr/(<\s*nowiki[^<>]*>.*?<\s*\/nowiki[^<>]*>)/s;
my $preRegex = qr/(<\s*pre[^<>]*>.*?<\s*\/pre[^<>]*>)/s;

# This function transcludes all templates in a given string and returns a fully expanded
# text. 

# It's called recursively, so we have a $templateRecursionLevel parameter to track the 
# recursion depth and break out in case it gets too deep.

sub includeTemplates(\%$$) {
  my ($page, $text, $templateRecursionLevel) = @_;

  if( $templateRecursionLevel > $maxTemplateRecursionLevels ) {

    # Ignore this template if limit is reached 

    # Since we limit the number of levels of template recursion, we might end up with several
    # un-instantiated templates. In this case we simply eliminate them - however, we do so
    # later, in function 'postprocessText()', after extracting categories, links and URLs.

    &msg("WARNING", "Maximum template recursion level reached");
    return " ";
  }

  # Templates are frequently nested. Occasionally, parsing mistakes may cause template insertion
  # to enter an infinite loop, for instance when trying to instantiate Template:Country
  # {{country_{{{1}}}|{{{2}}}|{{{2}}}|size={{{size|}}}|name={{{name|}}}}}
  # which is repeatedly trying to insert template "country_", which is again resolved to
  # Template:Country. The straightforward solution of keeping track of templates that were
  # already inserted for the current article would not work, because the same template
  # may legally be used more than once, with different parameters in different parts of
  # the article. Therefore, we simply limit the number of iterations of nested template
  # inclusion.

  # Note that this isn't equivalent to MediaWiki handling of template loops 
  # (see http://meta.wikimedia.org/wiki/Help:Template), but it seems to be working well enough for us.
  
  my %nowikiChunksReplaced = ();
  my %preChunksReplaced = ();

  # Hide template invocations nested inside <nowiki> tags from the s/// operator. This prevents 
  # infinite loops if templates include an example invocation in <nowiki> tags.

  &extractTags(\$preRegex, \$text, \%preChunksReplaced);
  &extractTags(\$nowikiRegex, \$text, \%nowikiChunksReplaced);

  my $invocation = 0;
  my $new_text = "";
  my $token;

  for $token ( &splitOnTemplates($text) ) {
    if( $invocation ) {
      $new_text .= &instantiateTemplate($token, $page, $templateRecursionLevel);
      $invocation = 0;
    } else {
      $new_text .= $token;
      $invocation = 1;
    }
  }

  # $text =~ s/$templateRegex/&instantiateTemplate($1, $refToId, $refToTitle, $templateRecursionLevel)/segx;

  &replaceTags(\$new_text, \%nowikiChunksReplaced);
  &replaceTags(\$new_text, \%preChunksReplaced);

  # print LOGF "Finished with templates level $templateRecursionLevel\n";
  # print LOGF "#########\n\n";
  # print LOGF "$text";
  # print LOGF "#########\n\n";
  
  my $text_len = length $new_text;
  &msg("DEBUG", "Text length after templates level $templateRecursionLevel: $text_len chars");
  
  return $new_text;
}

}

sub instantiateTemplate($\%$) {
  my ($templateInvocation, $page, $templateRecursionLevel) = @_;

  my $len = length( $templateInvocation );
  if($len > 32767) {
    # Some {{#switch ... }} statements are excesivelly long and usually do not produce anything
    # useful. Plus they can cause segfauls in older versions of Perl.

    &msg("WARNING", "Ignoring long template invocation=$templateInvocation");
    return "";
  }

  # Clean the invocation string: remove braces that were also matched by $RE{balanced} and 
  # ignore optional whitespace before the template name.
  
  $templateInvocation =~ s/^\s*//;
  
  &msg("DEBUG", "Template recursion level $templateRecursionLevel");
  &msg("DEBUG", "Instantiating template=$templateInvocation");

  # The template name extends up to the first pipeline symbol (if any).
  # Template parameters go after the "|" symbol.
  
  # Template parameters often contain URLs, internal links, or just other useful text,
  # whereas the template serves for presenting it in some nice way.
  # Parameters are separated by "|" symbols. However, we cannot simply split the string
  # on "|" symbols, since these frequently appear inside internal links. Therefore, we split
  # on those "|" symbols that are not inside [[...]]. 
      
  # Note that template name can also contain internal links (for example when template is a
  # parser function: "{{#if:[[...|...]]|...}}". So we use the same mechanism for splitting out
  # the name of the template as for template parameters.
  
  # Same goes if template parameters include other template invocations.

  # We also trim leading and trailing whitespace from parameter values.

  my @rawTemplateParams = map { s/^\s+//; s/\s+$//; $_; } &splitTemplateInvocation($templateInvocation);
  return "" unless @rawTemplateParams;
  
  # We now have the invocation string split up on | in the @rawTemplateParams list.
  # String before the first "|" symbol is the title of the template.
  my $templateTitle = shift(@rawTemplateParams);
  $templateTitle = &includeTemplates($page, $templateTitle, $templateRecursionLevel + 1);

  my $result = &includeParserFunction(\$templateTitle, \@rawTemplateParams, $page, $templateRecursionLevel);

  # If this wasn't a parser function call, try to include a template.
  if ( not defined($result) ) {
    &computeFullyQualifiedTemplateTitle(\$templateTitle);

    my $overrideResult = $overrideTemplates{$templateTitle};
    if(defined $overrideResult) {
      &msg("WARNING", "Overriding template $templateTitle");
      return $overrideResult;
    }
  
    my %templateParams;
    &parseTemplateInvocation(\@rawTemplateParams, \%templateParams);

    &includeTemplateText(\$templateTitle, \%templateParams, $page, \$result);
  }

  $result = &includeTemplates($page, $result, $templateRecursionLevel + 1);

  return $result;  # return value
}

sub switchParserFunction {
  # Code ported from ParserFunctions.php
  # Documentation at http://www.mediawiki.org/wiki/Help:Extension:ParserFunctions#.23switch:
  
  my ($refToRawParameterList, $page, $templateRecursionLevel) = @_;

  my $primary = shift( @$refToRawParameterList );

  my @parts;
  my $found;
  my $default;

  for my $param (@$refToRawParameterList) {
    @parts = split(/\s*=\s*/, $param, 2);
    if( $#parts == 1 ) {
      my $lvalue = &includeTemplates($page, $parts[0], $templateRecursionLevel + 1);
      # Found "="
      if( $found || $lvalue eq $primary ) {
        # Found a match, return now
        return $parts[1];
      } elsif( $parts[0] =~ /^#default/ ) {
        $default = $parts[1];
      } 
      # else wrong case, continue
    } elsif( $#parts == 0 ) {
      my $lvalue = &includeTemplates($page, $parts[0], $templateRecursionLevel + 1);
      # Multiple input, single output
      # If the value matches, set a flag and continue
      if( $lvalue eq $primary ) {
        $found = 1;
      }
    }
  }
  # Default case
  # Check if the last item had no = sign, thus specifying the default case
  if( $#parts == 0 ) {
    return $parts[0];
  } elsif( $default ) {
    return $default;
  } else {
    return '';
  }
}

sub includeParserFunction(\$\%\%$\$) {
  my ($refToTemplateTitle, $refToRawParameterList, $page, $templateRecursionLevel) = @_;

  # Parser functions have the same syntax as templates, except their names start with a hash
  # and end with a colon. Everything after the first colon is the first argument.

  # Parser function invocation can span more than one line, hence the /s modifier

  # http://meta.wikimedia.org/wiki/Help:ParserFunctions
  
  my $result = undef;

  if ( $$refToTemplateTitle =~ /^\#([a-z]+):\s*(.*?)\s*$/s ) {
    my $functionName = $1;
    unshift( @$refToRawParameterList, &includeTemplates($page, $2, $templateRecursionLevel + 1) );

    &msg("DEBUG", "Evaluating parser function #$functionName");

    if ( $functionName eq 'if' ) {

      my $valueIfTrue = $$refToRawParameterList[1];
      my $valueIfFalse = $$refToRawParameterList[2];

      # print LOGF "If condition: $2\n";
      # if ( defined($valueIfTrue) ) {
      #   print LOGF "If true: $valueIfTrue\n";
      # }
      # if ( defined($valueIfFalse) ) {
      #   print LOGF "If false: $valueIfFalse\n";
      # }

      if ( length($$refToRawParameterList[0]) > 0 ) {
        # The {{#if:}} function is an if-then-else construct. The applied condition is 
        # "The condition string is non-empty". 

        if ( defined($valueIfTrue) && ( length($valueIfTrue) > 0 ) ) {
          $result = $valueIfTrue;
        } else {
          $result = "";
        }
      } else {
        if ( defined($valueIfFalse) && ( length($valueIfFalse) > 0 ) ) {
          $result = $valueIfFalse;
        } else {
          $result = "";
        }
      }
    } elsif ( $functionName eq 'ifeq' ) {

      my $valueIfTrue = $$refToRawParameterList[2];
      my $valueIfFalse = $$refToRawParameterList[3];

      # Already has templates expanded.
      my $lvalue = $$refToRawParameterList[0];
      my $rvalue = $$refToRawParameterList[1];

      if ( defined($rvalue ) ) {
        $rvalue = &includeTemplates($page, $rvalue, $templateRecursionLevel + 1);

        # lvalue is always defined
        if ( $lvalue eq $rvalue ) {
          # The {{#ifeq:}} function is an if-then-else construct. The applied condition is 
          # "is rvalue equal to lvalue". Note that this does only string comparison while MediaWiki
          # implementation also supports numerical comparissons.

          if ( defined($valueIfTrue) && ( length($valueIfTrue) > 0 ) ) {
            $result = $valueIfTrue;
          } else {
            $result = "";
          }
        } else {
          if ( defined($valueIfFalse) && ( length($valueIfFalse) > 0 ) ) {
            $result = $valueIfFalse;
          } else {
            $result = "";
          }
        }
      } else {
        $result = "";
      }
    } elsif ( $functionName eq 'switch' ) {
      $result = &switchParserFunction($refToRawParameterList, $page, $templateRecursionLevel);
    } elsif ( $functionName eq 'language' ) {
      # {{#language: code}} gives the language name of selected RFC 3066 language codes, 
      # otherwise it returns the input value as is.

      my $code = $$refToRawParameterList[0];

      $result = &languageName($code);
    } else {

      &msg("WARNING", "Function #$functionName not supported");

      # Unknown function -- fall back by inserting first argument, if available. This seems
      # to be the most sensible alternative in most cases (for example in #time and #date)

      if ( exists($$refToRawParameterList[1]) && ( length($$refToRawParameterList[1]) > 0 ) ) {
        $result = $$refToRawParameterList[1];
      } else {
        $result = "";
      }
    }

    # print LOGF "Function returned: $result\n";

  } elsif ( $$refToTemplateTitle =~ /^urlencode:\s*(.*)/ ) {
    # This function is used in some pages to construct links
    # http://meta.wikimedia.org/wiki/Help:URL

    $result = $1;
    &msg("DEBUG", "URL encoding string $result");

    $result =~ s/([^A-Za-z0-9])/sprintf("%%%02X", ord($1))/seg;
  } elsif ( lc $$refToTemplateTitle eq "pagename" ) {
    # FIXME: {{FULLPAGENAME}} returns full name of the page (including the 
    # namespace prefix. {{PAGENAME}} returns only the title.
    #
    # Also consider supporting {{SERVER}}, which is used to construct edit
    # links in some stub templates (external URLs aren't removed properly
    # without it)
    $result = $page->{title};
  }

  return $result;
}

sub noteTemplateInclude(\$\%\%) {
  my ($refToTemplateId, $page, $refToParameterHash) = @_;

  my $templates = $page->{templates};
  
  $templates->{$$refToTemplateId} = [] unless( defined( $templates->{$$refToTemplateId} ) );

  push( @{$templates->{$$refToTemplateId}}, $refToParameterHash );
}

sub includeTemplateText(\$\%\%\$$) {
  my ($refToTemplateTitle, $refToParameterHash, $page, $refToResult) = @_;

  &normalizeTitle($refToTemplateTitle);
  my $includedPageId = &resolveLink($refToTemplateTitle);

  if ( defined($includedPageId) && exists($templates{$includedPageId}) ) {

    # Log which template has been included in which page with which parameters
    &noteTemplateInclude(\$includedPageId, $page, $refToParameterHash);

    # OK, perform the actual inclusion with parameter substitution. 

    # First we retrieve the text of the template
    $$refToResult = $templates{$includedPageId};

    # Substitute template parameters
    if( &templateParameterRecursion($refToResult, $refToParameterHash, 1) ) {
      &msg("WARNING", "Maximum template parameter recursion level reached");
    }

  } else {
    # The page being included cannot be identified - perhaps we skipped it (because currently
    # we only allow for inclusion of pages in the Template namespace), or perhaps it's
    # a variable name like {{NUMBEROFARTICLES}}. Just remove this inclusion directive and
    # replace it with a space
    &msg("WARNING", "Template '$$refToTemplateTitle' is not available for inclusion");
    $$refToResult = " ";
  }
}

sub computeFullyQualifiedTemplateTitle(\$) {
  my ($refToTemplateTitle) = @_;

  # Determine the namespace of the page being included through the template mechanism

  my $namespaceSpecified = 0;

  if ($$refToTemplateTitle =~ /^:(.*)$/) {
    # Leading colon by itself implies main namespace, so strip this colon
    $$refToTemplateTitle = $1;
    $namespaceSpecified = 1;
  } elsif ($$refToTemplateTitle =~ /^([^:]*):/) {
    # colon found but not in the first position - check if it designates a known namespace
    my $prefix = $1;
    &normalizeNamespace(\$prefix);
    $namespaceSpecified = &isKnownNamespace(\$prefix);
  }

  # The case when the page title does not contain a colon at all also falls here.

  if ($namespaceSpecified) {
    # OK, the title of the page being included is fully qualified with a namespace
  } else {
    # The title of the page being included is NOT in the main namespace and lacks
    # any other explicit designation of the namespace - therefore, it is resolved
    # to the Template namespace (that's the default for the template inclusion mechanism).
    $$refToTemplateTitle = $langDB{'templateNamespace'} . ":" . $$refToTemplateTitle;
  }
}

sub extractCategories(\%) {
  my ($page) = @_;

  # Remember that namespace names are case-insensitive, hence we're matching with "/i".
  # The first parameter to 'collectCategory' is passed by value rather than by reference,
  # because it might be dangerous to pass a reference to $1 in case it might get modified
  # (with unclear consequences).
  my $categoryNamespace = $langDB{'categoryNamespace'};

  $page->{categories} = [];

  $page->{text} =~ s/\[\[(?:\s*)($categoryNamespace:.*?)\]\]/&collectCategory($1, $page)/ieg;

  # We don't accumulate categories directly in a hash table, since this would not preserve
  # their original order of appearance.
  &removeDuplicatesAndSelf($page->{categories}, $page->{id});
}

sub collectCategory($\@) {
  my ($catName, $page) = @_;

  if ($catName =~ /^(.*)\|/) {
    # Some categories contain a sort key, e.g., [[Category:Whatever|*]] or [[Category:Whatever| ]]
    # In such a case, take only the category name itself.
    $catName = $1;
  }

  &normalizeTitle(\$catName);

  my $catId = &resolveLink(\$catName);
  if ( defined($catId) ) {
    push(@{$page->{categories}}, $catId);
  } else {
    &msg("WARNING", "unknown category '$catName'");
  }

  # The return value is just a space, because we remove categories from the text
  # after we collected them
  " ";
}

BEGIN {

my $internalLinkRegex = qr/
                             (\w*)            # words may be glued to the beginning of the link,
                                              # in which case they become part of the link
                                              # e.g., "ex-[[Giuseppe Mazzini|Mazzinian]] "
                             \[\[
                                   ([^\[]*?)  # the link text can be any chars except an opening bracket,
                                              # this ensures we correctly parse nested links (see comments above)
                             \]\]
                             (\w*)            # words may be glued to the end of the link,
                                              # in which case they become part of the link
                                              # e.g., "[[public transport]]ation"
                         /sx;

sub extractWikiLinks(\$\@$\@$) {
  my ($refToText, $refToAnchorTextArray, $refToInterwikiLinksArray) = @_;

  # For each internal link outgoing from the current article we create an entry in
  # the AnchorTextArray (a reference to an anonymous hash) that contains target id and anchor 
  # text associated with it.
  #
  # This way we can have more than one anchor text per link

  # Link definitions may span over adjacent lines and therefore contain line breaks,
  # hence we use the /s modifier.
  # Occasionally, links are nested, e.g.,
  # [[Image:kanner_kl2.jpg|frame|right|Dr. [[Leo Kanner]] introduced the label ''early infantile autism'' in [[1943]].]]
  # In order to prevent incorrect parsing, e.g., "[[Image:kanner_kl2.jpg|frame|right|Dr. [[Leo Kanner]]",
  # we extract links in several iterations of the while loop, while the link definition requires that
  # each pair [[...]] does not contain any opening braces.
  
  1 while ( $$refToText =~ s/$internalLinkRegex/&collectWikiLink($1, $2, $3, 
                                                                     $refToAnchorTextArray, 
                                                                     $refToInterwikiLinksArray,
                                                                     $-[0])/eg );
}

}

sub collectWikiLink($$$\@\@$) {
  my ($prefix, $link, $suffix, $refToAnchorTextArray, $refToInterwikiLinksArray,
      $linkLocation) = @_;

  my $originalLink = $link;
  my $result = "";

  # Link definitions may span over adjacent lines and therefore contain line breaks,
  # hence we use the /s modifier on most matchings.

  # There are some special cases when the link may be preceded with a colon.
  # Known cases:
  # - Linking to a category (as opposed to actually assigning the current article
  #   to a category) is performed using special syntax [[:Category:...]]
  # - Linking to other languages, e.g., [[:fr:Wikipedia:Aide]]
  #   (without the leading colon, the link will go to the side menu
  # - Linking directly to the description page of an image, e.g., [[:Image:wiki.png]]
  # In all such cases, we strip the leading colon.

  # just strip this initial colon (as well as any whitespace preceding it)
  $link =~ s/^\s*:?//;
  if ( !$link ) {
    # Empty link, bail out.
    return "";
  }

  $link = &resolveNamespaceAliases($link);

  # Alternative text may be available after the pipeline symbol.
  # If the pipeline symbol is only used for masking parts of
  # the link name for presentation, we still consider that the author of the page
  # deemed the resulting text important, hence we always set this variable when
  # the pipeline symbol is present.
  my $alternativeTextAvailable = 0;

  my $isImageLink = 0;
  my $interwikiRecognized = 0;
  my $interwikiTitle;

  my $imageNamespace = $langDB{'imageNamespace'};
  if ($link =~ /^$imageNamespace:/) {
    $isImageLink = 1;
  }

  # "-1" parameter permits empty trailing fields (important for pipeline masking)
  my @pipeFields = split(/\|/, $link, -1);

  # Text before the first "|" symbol contains link destination.
  $link = shift(@pipeFields);
  if ( !$link ) {
    # Empty link, bail out.
    return "";
  }

  # If the link contains a section reference, adjust the link to point to the page as a whole and
  # exract the section
  my $section;

  ( $link, $section ) = split(/#/, $link, 2);
  if ( defined($section) ) {

    # Check if the link points to a section on the current page, and if so - ignore it.
    if (length($link) == 0 && ! $alternativeTextAvailable) {
      # This is indeed a link pointing to an section on the current page.
      # The link is thus cleared, so that it will not be resolved and collected later.
      # For section links to the same page, discard the leading '#' symbol, and take
      # the rest as the text - but only if no alternative text was provided for this link.
      $result = $section;
    }
  }
  
  if ($isImageLink) {
    # Image links have to be parsed separately, because anchors can contain parameters (size, type, etc.)
    # which we exclude in a separate function.
    $result = &parseImageParameters(\@pipeFields);

    if( length($result) > 0 ) {
      $alternativeTextAvailable = 1;
    } 
  } else {
    # Check if this is an interwiki link.
    my $wikiName;
    ( $wikiName, $interwikiTitle ) = &parseInterwiki($link);
    
    if( defined( $wikiName ) ) {
      $wikiName = lc($wikiName);

      my $normalizedTitle = $interwikiTitle;
      &normalizeTitle(\$normalizedTitle);

      $interwikiRecognized = 1;

      if( defined( $refToInterwikiLinksArray ) ) {
        push( @$refToInterwikiLinksArray, { targetWiki => $wikiName, targetTitle => $normalizedTitle } );
      }
    }

    # Extract everything after the last pipeline symbol. Normal pages shouldn't have more than one
    # pipeline symbol, but remove extra pipes in case of broken or unknown new markup. Discard
    # all text before the last pipeline.
    $result = pop(@pipeFields);

    if( defined($result) ) {

      # pipeline found, see comment above
      $alternativeTextAvailable = 1; 

      if( length($result) == 0 ) {
        # Pipeline found, but no text follows.

        if( $interwikiRecognized ) {
          # For interwiki links, pipeline masking is performed simply by using the page title
          # instead of the complete link.
          $result = $interwikiTitle;
        } elsif ( not defined($section) ) {
          # If the "|" symbol is not followed by some text, then it masks the namespace
          # as well as any text in parentheses at the end of the link title.
          # However, pipeline masking is only invoked if the link does not contain a section 
          # reference, hence the additional condition in the 'if' statement.
          &performPipelineMasking(\$link, \$result);
        } else {
          # If the link contains an anchor, then masking is not invoked, and we take the entire link
          $result = $link;
        }
      }
    } else {
      # the link text does not contain the pipeline, so take it as-is
      $result = $link;
    }
  }

  # Now collect the link, or links if the original link is in the date format
  # and specifies both day and year. In the latter case, the function for date
  # normalization may also modify the link text ($result), and may collect more
  # than one link (one for the day, another one for the year).
  my $dateRecognized = 0;

  my $targetId = undef;

  # Alternative text (specified after pipeline) blocks normalization of dates.
  # We also perform a quick check - if the link does not start with a digit,
  # then it surely does not contain a date
  if ( ( !$interwikiRecognized ) and ( !$alternativeTextAvailable ) and ( $link =~ /^\d/ ) ) {
    $dateRecognized = &normalizeDates(\$link, \$result, \$targetId, $refToAnchorTextArray, $linkLocation);
  }

  # If a date (either day or day + year) or interwiki link was recognized, then no further
  # processing is necessary
  if (! $dateRecognized and ! $interwikiRecognized ) {
    &normalizeTitle(\$link);

    $targetId = &resolveAndCollectInternalLink(\$link);

    # Wikipedia pages contain many links to other Wiki projects (especially Wikipedia in
    # other languages). While these links are not resolved to valid pages, we also want
    # to ignore their text. However, simply discarding the text of all links that cannot
    # be resolved would be overly aggressive, as authors frequently define phrases as links
    # to articles that don't yet exist, in the hope that they will be added later.
    # Therefore, we formulate the following conditions that must hold simultaneously
    # for discarding the text of a link:
    # 1) the link was not resolved to a valid id
    # 2) the link does not contain alternative text (if it did, then the text is probably
    #    important enough to be retained)
    # 3) the link contains a colon - this is a very simple heuristics for identifying links to
    #    other Wiki projects, other languages, or simply other namespaces within current Wikipedia.
    #    While this method is not fool-proof (there are regular pages in the main namespace
    #    that contain a colon in their title), we believe this is a reasonable tradeoff.
    if ( !defined($targetId) && ! $alternativeTextAvailable && $link =~ /:/ ) {
      $result = "";
      &msg("DEBUG", "Discarding text for link '$originalLink'");
    } else {
      # finally, add the text originally attached to the left and/or to the right of the link
      # (if the link represents a date, then it has not text glued to it, so it's OK to only
      # use the prefix and suffix here)

      # But we only do this if it's not an image link. Anchor text for image links is used as
      # image caption.
      if ( ! $isImageLink ) {
        $result = $prefix . $result . $suffix;
      }
    }

    # We log anchor text only if it would be visible in the web browser. This means that for an
    # link to an ordinary page we log the anchor whether an alternative text was available or not
    # (in which case Wikipedia shows just the name of the page).
    #
    # Note that for a link to an image that has no alternative text, we log an empty string.
    # This is important because otherwise the linkLocation wouldn't get stored.

    my $postprocessedResult = $result;
    # anchor text doesn't need escaping of XML characters,
    # hence the second function parameter is 0
    &postprocessText(\$postprocessedResult, 0, 0);

    $targetId = undef unless $targetId;
    push(@$refToAnchorTextArray, { targetId     => $targetId, 
                                   anchorText   => $postprocessedResult, 
                                   linkLocation => $linkLocation } );
  }

  # Mark internal links with special magic words that are later converted to XML tags
  # in postprocessText()

  if ( defined($targetId) and length($result) > 0 ) {
    return ".pAriD=\"$targetId\".$result.pArenD."; 
  } else {
    return $result;
  }
}

sub performPipelineMasking(\$\$) {
  my ($refToLink, $refToResult) = @_;

  # First check for presence of a namespace
  if ($$refToLink =~ /^([^:]*):(.*)$/) {
    my $namespaceCandidate = $1;
    my $rest = $2;

    &normalizeNamespace(\$namespaceCandidate);
    if ( &isKnownNamespace(\$namespaceCandidate) ) {
      $$refToResult = $rest; # take the link text without the namespace
    } else {
      $$refToResult = $$refToLink; # otherwise, take the entire link text (for now)
    }
  } else {
    $$refToResult = $$refToLink; # otherwise, take the entire link text (for now)
  }

  # Now check if there are parentheses at the end of the link text
  # (we now operate on $$refToResult, because we might have stripped the leading
  # namespace in the previous test).
  if ($$refToResult =~ /^                  # the beginning of the string
                          (.*)             # the text up to the last pair of parentheses
                          \(               # opening parenthesis
                              (?:[^()]*)   #   the text in the parentheses
                          \)               # closing parenthesis
                          (?:\s*)          # optional trailing whitespace, just in case
                        $                  # end of string
                       /x) {
    $$refToResult = $1; # discard the text in parentheses at the end of the string
  }
}

# Collects only links that do not point to a template (which besides normal and local pages
# also have an ID in %title2id hash.

sub resolveAndCollectInternalLink(\$) {
  my ($refToLink) = @_;

  my $targetId = &resolveLink($refToLink);
  if ( defined($targetId) ) {
    if ( exists($templates{$targetId}) ) {
      &msg("DEBUG", "Ignoring link to a template '$$refToLink'");
      $targetId = undef;
    }
  } else {
    # Some cases in this category that obviously won't be resolved to legal ids:
    # - Links to namespaces that we don't currently handle
    #   (other than those for which 'isNamespaceOK' returns true);
    #   media and sound files fall in this category
    # - Links to other languages, e.g., [[de:...]]
    # - Links to other Wiki projects, e.g., [[Wiktionary:...]]
    &msg("WARNING", "unknown link '$$refToLink'");
  }

  $targetId;  # return value
}

# Dates can appear in several formats
# 1) [[July 20]], [[1969]]
# 2) [[20 July]] [[1969]]
# 3) [[1969]]-[[07-20]]
# 4) [[1969-07-20]]
# The first one is handled correctly without any special treatment,
# so we don't even check for it here.
# In (2) and (3), we only normalize the day, because it will be parsed separately from the year.
# This function is only invoked if the link has no alternative text available, therefore,
# we're free to override the result text.
sub normalizeDates(\$\$\$\@$) {
  my ($refToLink, $refToResultText, $refToTargetId, $refToAnchorTextArray, $linkLocation) = @_;

  my $dateRecognized = 0;

  if ($$refToLink =~ /^([0-9]{1,2})\s+([A-Za-z]+)$/) {
    my $day = $1;
    my $month = ucfirst(lc($2));

    if ( defined($monthToNumDays{$month}) &&
         1 <= $day && $day <= $monthToNumDays{$month} ) {
      $dateRecognized = 1;

      $$refToLink = "$month $day";
      $$refToResultText = "$month $day";

      my $targetId = &resolveAndCollectInternalLink($refToLink);

      $$refToTargetId = $targetId;
      push(@$refToAnchorTextArray, { targetId     => $targetId, 
                                     anchorText   => $$refToResultText,
                                     linkLocation => $linkLocation } );
    } else {
      # this doesn't look like a valid date, leave as-is
    }
  } elsif ($$refToLink =~ /^([0-9]{1,2})\-([0-9]{1,2})$/) {
    my $monthNum = int($1);
    my $day = $2;

    if ( defined($langDB{'numberToMonth'}->{$monthNum}) ) {
      my $month = $langDB{'numberToMonth'}->{$monthNum};
      if (1 <= $day && $day <= $monthToNumDays{$month}) {
        $dateRecognized = 1;

        $$refToLink = "$month $day";
        # we add a leading space, to separate the preceding year ("[[1969]]-" in the example")
        # from the day that we're creating
        $$refToResultText = " $month $day";

        my $targetId = &resolveAndCollectInternalLink($refToLink);
        $$refToTargetId = $targetId; 
        push(@$refToAnchorTextArray, { targetId     => $targetId, 
                                       anchorText   => $$refToResultText,
                                       linkLocation => $linkLocation } );
      } else {
        # this doesn't look like a valid date, leave as-is
      }
    } else {
      # this doesn't look like a valid date, leave as-is
    }
  } elsif ($$refToLink =~ /^([0-9]{3,4})\-([0-9]{1,2})\-([0-9]{1,2})$/) {
    my $year = $1;
    my $monthNum = int($2);
    my $day = $3;

    if ( defined($langDB{'numberToMonth'}->{$monthNum}) ) {
      my $month = $langDB{'numberToMonth'}->{$monthNum};
      if (1 <= $day && $day <= $monthToNumDays{$month}) {
        $dateRecognized = 1;

        $$refToLink = "$month $day";
        # the link text is combined from the day and the year
        $$refToResultText = "$month $day, $year";

        my $targetId;

        # collect the link for the day
        $targetId = &resolveAndCollectInternalLink($refToLink);
        $$refToTargetId = $targetId; 
        push(@$refToAnchorTextArray, { targetId     => $targetId, 
                                       anchorText   => $$refToLink,
                                       linkLocation => $linkLocation } );

        # collect the link for the year
        $targetId = &resolveAndCollectInternalLink(\$year);
        $$refToTargetId = $targetId; 
        push(@$refToAnchorTextArray, { targetId     => $targetId, 
                                       anchorText   => $year,
                                       linkLocation => $linkLocation } );
      } else {
        # this doesn't look like a valid date, leave as-is
      }
    } else {
      # this doesn't look like a valid date, leave as-is
    }
  }

  $dateRecognized;  # return value
}

BEGIN {
  # Allowed URL protocols (copied from DefaultSettings.php)

  # Note that Wikipedia is case sensitive regarding URL protocols (e.g., [Http://...] will not produce 
  # an external link) 

  my %urlProtocols = ( 'http' => 1, 'https' => 1, 'ftp' => 1, 'irc' => 1, 'gopher' => 1, 'telnet' => 1, 
                       'nntp' => 1, 'worldwind' => 1, 'mailto' => 1, 'news' => 1 );

  # A regex that matches all valid URLs. The first group is
  my $urlRegex = qr/[a-z]+:(?:[\w!\$\&\'()*+,-.\/:;=?\@\_`~]|%[a-fA-F0-9]{2})+/;

  # MediaWiki supports two kinds of external links: implicit and explicit.

  # Explicit links can have anchors, and have format like [http://www.cnn.com CNN]. Anchor is the text from
  # the first whitespace to the end of the bracketed expression.

  # Note that no whitespace is allowed before the URL.
  my $urlSequence1 = qr/\[($urlRegex)(.*?)\]/;

  # Implicit links are normal text that is recognized as a valid URL.
  my $urlSequence2 = qr/($urlRegex)/;

  sub extractUrls(\%) {
    my ($page) = @_;

    $page->{externalLinks} = [];
    $page->{bareUrls} = [];

    # First we handle the case of URLs enclosed in single brackets, with or without the description.
    # Examples: [http://www.cnn.com], [ http://www.cnn.com  ], [http://www.cnn.com  CNN Web site]
    $page->{text} =~ s/$urlSequence1/&collectUrlFromBrackets($1, $2, $page)/eg;

    # Now we handle standalone URLs (those not enclosed in brackets)
    # The $urlTemrinator is matched via positive lookahead (?=...) in order not to remove
    # the terminator symbol itself, but rather only the URL.
    $page->{text} =~ s/$urlSequence2/&collectStandaloneUrl($1, $page)/eg;

    &removeDuplicatesAndSelf($page->{bareUrls}, undef);
  }

  sub collectUrlFromBrackets($$\%) {
    my ($url, $anchor, $page) = @_;

    # Extract protocol - this is the part of the string before the first ':' because of the
    # $urlRegex above.
   
    my @temp = split(/:/, $url, 2);
    my $urlProtocol = $temp[0];

    if( exists( $urlProtocols{$urlProtocol} ) ) {
      push(@{$page->{bareUrls}}, $url);

      my $anchorTrimmed = &trimWhitespaceBothSides($anchor);

      # See if there is anything left of the anchor and log to file
      if( length( $anchorTrimmed ) > 0 ) {
        push(@{$page->{externalLinks}}, { anchor => $anchorTrimmed, url => $url } );
      } else {
        push(@{$page->{externalLinks}}, { url => $url } );
      }
      return $anchor;
    } else {
      # Return the original string, just like MediaWiki does.
      return "[$url$anchor]";
    }
  }

  # Same procedure as for extracting URLs from brackets, except that we can't have an 
  # anchor in this case.

  sub collectStandaloneUrl($\%) {
    my ($url, $page) = @_;

    my @temp = split(/:/, $url, 2);
    my $urlProtocol = $temp[0];

    if( exists( $urlProtocols{$urlProtocol} ) ) {
      push(@{$page->{bareUrls}}, $url);
      push(@{$page->{externalLinks}}, { url => $url } );
      return "";
    } else {
      # Don't replace anything
      return "$url";
    }
  }
}

sub parseDisambig(\%) {
	my ($page) = @_;

  $page->{disambigLinks} = [];

	for my $line ( split(/\n/, $page->{text}) ) {

		if ( $line =~ /^\s*(?:
					                (\*\*)|
					                (\#\#)|
                          (\:\#)|
                          (\:\*)|
                          (\#)|
                          (\*)
                        )/ix ) {

      my @disambigLinks;

      &extractWikiLinks(\$line, \@disambigLinks, undef);

      push(@{$page->{disambigLinks}}, \@disambigLinks)
		}
	}
}

sub postprocessText(\$$$) {
  my ($refToText, $whetherToEncodeXmlChars, $whetherToPreserveInternalTags) = @_;

  # Eliminate all <includeonly> and <onlyinclude> fragments, because this text
  # will not be included anywhere, as we already handled all inclusion directives
  # in function 'includeTemplates'.
  # This block can easily span several lines, hence the "/s" modifier.
  $$refToText =~ s/<includeonly>(?:.*?)<\/includeonly>/ /sg;
  $$refToText =~ s/<onlyinclude>(?:.*?)<\/onlyinclude>/ /sg;

  # <noinclude> fragments remain, but remove the tags per se
  # We block the code below, as <noinclude> tags will anyway be thrown away later,
  # when we eliminate all remaining tags.
  ### This block can easily span several lines, hence the "/s" modifier
  ### $$refToText =~ s/<noinclude>(.*?)<\/noinclude>/$1/sg;

  # replace <br> and <br /> directives with new paragraph
  $$refToText =~ s/<br(?:\s*)(?:[\/]?)>/\n\n/g;

  # Remove tables and math blocks, as they often carry a lot of noise
  &eliminateTables($refToText);
  &eliminateMath($refToText);

  # Since we limit the number of levels of template recursion, we might end up with several
  # un-instantiated templates. In this case we simply eliminate them now.
  # Because templates may be nested, we eliminate them iteratively by starting from the most
  # nested one (hence the 'while' loop).
  #    OLD comments and code:
  #    For the same reason, we also require that the body of a template does not contain
  #    opening braces (hence "[^\{]", any char except opening brace).
  #    1 while ($$refToText =~ s/\{\{(?:[^\{]*?)\}\}/ /sg);
  #    END OF old comments and code
  # We also require that the body of a template does not contain the template opening sequence
  # (two successive opening braces - "\{\{"). We use negative lookahead to achieve this.
  1 while ($$refToText =~ s/\{\{
                                 (?:
                                     (?:
                                         (?!
                                             \{\{
                                         )
                                         .
                                     )*?
                                 )
                            \}\}
                           / /sgx);

  # Remove any other <...> tags - but keep the text they enclose
  # (the tags are replaced with spaces to prevent adjacent pieces of text
  # from being glued together).
  $$refToText =~ s/<\/?[a-z][^<>]*?>/ /sg;

  # Change markup on bold/italics emphasis. We probably don't need to distinguish
  # these 3 types of emphasis, so we just replace all of them with a generic <em> tag.
  # IMPORTANT: If 'encodeXmlChars' has beeen called before this line, then remember that
  # the apostrophes were already quoted to "&apos;"
  $$refToText =~ s/'''''(.*?)'''''/$1/g;
  $$refToText =~ s/'''(.*?)'''/$1/g;
  $$refToText =~ s/''(.*?)''/$1/g;

  # Eliminate long sequences of newlines and whitespace.
  # Note that we don't want to replace sequences of spaces only, as this might make the text
  # less readable. Instead, we only eliminate sequences of whitespace that contain at least
  # two newlines.
  $$refToText =~ s/\s*\n\s*\n\s*/\n\n/g;

  # Eliminate XML entities such as "&nbsp;" , "&times;" etc. - otherwise,
  # in C++ code they will give rise to spurious words "nbsp", "times" etc.
  # Note that the standard entities - &amp; , &quot; , &apos; , &lt; and &gt;
  # are handled by the XML parser. All other entities, such as &nbsp; are passed
  # by the XML parser to the upper level (in case of Wikipedia pages,
  # to the rendering engine).
  # Note that in the raw XML text, these entities look like "&amp;nbsp;"
  # (i.e., with leading "&amp;"). XML parser replaces "&amp;" with "&",
  # so here in the code we see the entities as "&nbsp;".
  $$refToText =~ s{&                 # the entity starts with "&"
                   (\#?\w+)          # optional '#' sign (as in &#945;), followed by
                                     # an uninterrupted sequence of letters and/or digits
                   ;                 # the entity ends with a semicolon
                  }{ }gx;            # entities are replaced with a space

                                     # Replace with &logReplacedXmlEntity($1)
                                     # to log entity replacements.

  if ($whetherToEncodeXmlChars) {
    # encode text for XML
    &encodeXmlChars($refToText);
  }

  # NOTE that the following operations introduce XML tags, so they must appear
  # after the original text underwent character encoding with 'encodeXmlChars' !!
  
  # Convert magic words marking internal links to XML tags. Only properly nested 
  # tags are replaced.
  
  # We don't allow "==" to appear in links, since that could cause problems with
  # unbalanced <h1> and <internal> tags. There are very few legitimate links that
  # we ignore because of this.

  if( $whetherToPreserveInternalTags ) {
    1 while( 
      $$refToText =~ s/\.pAriD=&quot;([0-9]+)&quot;\.
                                                      (
                                                        (?:
                                                           (?!\.pAr)
                                                           (?!==)
                                                           .
                                                        )*?
                                                      )
                       \.pArenD\./<internal id="$1">$2<\/internal>/sgx );
  }

  # Remove any unreplaced magic words. This replace also removes tags, that for some
  # reason aren't properly nested (and weren't caught by replace above).

  $$refToText =~ s/\.pAriD=(?:&quot;|")[0-9]+(?:&quot;|")\.//g;
  $$refToText =~ s/\.pArenD\.//g;

  # Change markup for section headers.
  # Note that section headers may only begin at the very first position in the line
  # (not even after a space). Therefore, each header markup in the following commands
  # is prefixed with "^" to make sure it begins at the beginning of the line.
  # Since the text (e.g., article body) may contains multiple lines, we use
  # the "/m" modifier to allow matching "^" at embedded "\n" positions.
  $$refToText =~ s/^=====(.*?)=====/<h4>$1<\/h4>/mg;
  $$refToText =~ s/^====(.*?)====/<h3>$1<\/h3>/mg;
  $$refToText =~ s/^===(.*?)===/<h2>$1<\/h2>/mg;
  $$refToText =~ s/^==(.*?)==/<h1>$1<\/h1>/mg;
}

sub logReplacedXmlEntity($) {
  my ($xmlEntity) = @_;

  &msg("DEBUG", "ENTITY: &$xmlEntity;");

  " "; # return value - entities are replaced with a space
}

BEGIN {
  my $mathSequence1 = qr/<math>(?:.*?)<\/math>/ixs;

  # Making variables static for the function to avoid recompilation of regular expressions
  # every time the function is called.

  # Table definitions can easily span several lines, hence the "/s" modifier

  # Examples where the eliminateTables() fails:
  #
  # 1) Table block opened with <table> and closed with |} or vice versa
  # 2) Table block opened and never closed because it is:
  #        a) The last thing on the page and the author didn't bother to close it
  #        b) Closed automatically by a === heading or some other markup

  my $tableOpeningSequence1 = qr{<table(?:                       # either just <table>
                                          (?:\s+)(?:[^<>]*)      # or
                                       )?>}ix;                   # "<table" followed by at least one space
                                                                 # (to prevent "<tablexxx"), followed by
                                                                 # some optional text, e.g., table parameters
                                                                 # as in "<table border=0>"

# Version above is more efficient
#
#  my $tableOpeningSequence1 = qr{<table>                         # either just <table>
#                                 |                               # or
#                                 <table(?:\s+)(?:[^<>]*)>}ix;    # "<table" followed by at least one space
#                                                                 # (to prevent "<tablexxx"), followed by
#                                                                 # some optional text, e.g., table parameters
#                                                                 # as in "<table border=0>"

                                 # In the above definition, prohibiting '<' and '>' chars ([^<>]) ensures
                                 # that we do not consume more than necessary, so that in the example
                                 #  "<table border=0> aaa <table> bbb </table> ccc </table>"
                                 #  $1 is NOT extended to be "> aaa <table"

  my $tableClosingSequence1 = qr/<\/table>/i;
#  my $nonNestedTableRegex1 =
#    qr{$tableOpeningSequence1            # opening sequence
#       (
#         (?:                             # non-capturing grouper
#             (?!                         # lookahead negation
#                 $tableOpeningSequence1  # that's what we don't want to find inside a table definition
#             )
#             .                           # any character (such that there is no table opening sequence
#                                         #   after it because of the lookahead condition)
#         )*?                             # shortest match of such characters, up to the closing of a table
#       )
#       $tableClosingSequence1}sx;        # closing sequence

  my $tableOpeningSequence2 = qr/\{\|/;
# We must take care that the closing sequence doesn't match any template parameters inside a table 
# (example " {{{footnotes|}}}). So we only match on a single closing brace.
  my $tableClosingSequence2 = qr/\|\}(?!\})/;
#  my $nonNestedTableRegex2 =
#    qr{$tableOpeningSequence2            # opening sequence
#       (
#         (?:                             # non-capturing grouper
#             (?!                         # lookahead negation
#                 $tableOpeningSequence2  # that's what we don't want to find inside a table definition
#             )
#             .                           # any character (such that there is no table opening sequence
#                                         #   after it because of the lookahead condition)
#         )*?                             # shortest match of such characters, up to the closing of a table
#       )
#       $tableClosingSequence2}sx;        # closing sequence

  my $tableSequence1 = qr/$tableOpeningSequence1(?:.*?)$tableClosingSequence1/s;
  my $tableSequence2 = qr/$tableOpeningSequence2(?:
                                                      (?:
                                                            (?!\{\|)          # Don't match nested tables
                                                            .
                                                      )*?
                                                )$tableClosingSequence2/sx;

  sub eliminateTables(\$) {
    my ($refToText) = @_;

    # Sometimes, tables are nested, therefore we use a while loop to eliminate them
    # recursively, while requiring that any table we eliminate does not contain nested tables.
    # For simplicity, we assume that tables of the two kinds (e.g., <table> ... </table> and {| ... |})
    # are not nested in one another.

    my $tableRecursionLevels = 0;

    $$refToText =~ s/$tableSequence1/\n/g;

    # We only resolve nesting {| ... |} style tables, which are often nested in infoboxes and similar
    # templates.

    while ( ($tableRecursionLevels < $maxTableRecursionLevels) &&
            $$refToText =~ s/$tableSequence2/\n/g ) {
    
      $tableRecursionLevels++;
    }
  }

  sub eliminateMath(\$) {
    my ($refToText) = @_;

    $$refToText =~ s/$mathSequence1/ /sg;
  }

} # end of BEGIN block

# Removes elements of the second list from the first list.
# For efficiency purposes, the second list is converted into a hash.
sub removeElements(\@\@) {
  my ($refToArray, $refToElementsToRemove) = @_;

  my %elementsToRemove = ();
  my @result;

  # Construct the hash table for fast lookups
  my $item;
  foreach $item (@$refToElementsToRemove) {
    $elementsToRemove{$item} = 1;
  }

  foreach $item (@$refToArray) {
    if ( ! defined($elementsToRemove{$item}) ) {
      push(@result, $item);
    }
  }

  # overwrite the original array with the new one
  @$refToArray = @result;
}

sub getTimeAsString() {
  my $tm = localtime();
  my $result = sprintf("%02d:%02d:%02d", $tm->hour, $tm->min, $tm->sec);
}

# There are 3 kinds of related links that we look for:
# 1) Standalone (usually, at the beginning of the article or a section of it)
#    Ex: Main articles: ...
# 2) Inlined - text in parentheses inside the body of the article
#    Ex: medicine (see also: [[Health]])
# 3) Dedicated section
#    Ex: == See also ==
sub identifyRelatedArticles(\%) {
  my ($page) = @_;

  my $id = $page->{id};

  # We split the text into a set of lines. This also creates a copy of the original text -
  # this is important, since the function 'extractWikiLinks' modifies its argument,
  # so we'd better use it on a copy of the real article body.
  my @text = split("\n", $page->{text});
  my $line;

  my @relatedInternalLinks;

  # Standalone
  foreach $line (@text) {
    # We require that stanalone designators occur at the beginning of the line
    # (after at most a few characters, such as a whitespace or a colon),
    # and not just anywhere in the line. Otherwise, we would collect as related
    # those links that just happen to occur in the same line with an unrelated
    # string that represents a standalone designator.
    my $relatedRegex = $langDB{'relatedWording_Standalone'};
    if ($line =~ /^(?:.{0,5})($relatedRegex.*)$/) {
      my $str = $1; # We extract links from the rest of the line
      &msg("DEBUG", "Related(S): $id => $str");
      &extractWikiLinks(\$str, \@relatedInternalLinks, undef);
    }
  }

  # Inlined (in parentheses)
  foreach $line (@text) {
    my $relatedRegex = $langDB{'relatedWording_Inline'};
    while ($line =~ /\((?:\s*)($relatedRegex.*?)\)/g) {
      my $str = $1;
      &msg("DEBUG", "Related(I): $id => $str");
      &extractWikiLinks(\$str, \@relatedInternalLinks, undef);
    }
  }

  # Section
  # Sections can be at any level - "==", "===", "====" - it doesn't matter,
  # so it suffices to look for two consecutive "=" signs
  my $relatedSectionFound = 0;
  foreach $line (@text) {
    if ($relatedSectionFound) { # we're in the related section now
      if ($line =~ /==(?:.*?)==/) { # we just encountered the next section - exit the loop
        last;
      } else { # collect the links from the current line
        &msg("DEBUG", "Related(N): $id => $line");
        # 'extractWikiLinks' may modify its argument ('$line'), but it's OK
        # as we do not do any further processing to '$line' or '@text'
        &extractWikiLinks(\$line, \@relatedInternalLinks, undef);
      }
    } else { # we haven't yet found the related section
      if ($line =~ /==(.*?)==/) { # found some section header - let's check it
        my $sectionHeader = $1;
        my $relatedRegex = $langDB{'relatedWording_Section'};
        if ($sectionHeader =~ /$relatedRegex/) {
          $relatedSectionFound = 1;
          next; # proceed to the next line
        } else {
          next; # unrelated section - just proceed to the next line
        }
      } else {
        next; # just proceed to the next line - nothing to do
      }
    }
  }

  $page->{relatedArticles} = [];

  &getLinkIds($page->{relatedArticles}, \@relatedInternalLinks);
  &removeDuplicatesAndSelf($page->{relatedArticles}, $page->{id});
}

########################################################################

sub printUsage()
{
  print <<END
Wikiprep version $version, Copyright (C) 2007 Evgeniy Gabrilovich

Wikiprep comes with ABSOLUTELY NO WARRANTY; for details type 
'$0 -license'.

This is free software, and you are welcome to redistribute it
under certain conditions; type '$0 -license' for details.

Type '$0 -version' for version information.

USAGE: $0 <options> -f <XML file with page dump>

 e.g.  $0 -f pages_articles.xml
   or  $0 -f pages_articles.xml.bz2

Available options:
  -nourls        Don't extract external links (URLs) from pages. 
                 Reduces run-time by approximately one half.
  -log ARGS      Write a large log file with debug information.
                 Log can get approximately 3-4 times larger than
                 the XML dump, depending on the settings below.
  -compress      Enable compression on some of the output files.
  -lang LANG     Use language other than English. LANG is Wikipedia
                 language prefix (e.g. 'sl' for 'slwiki').
  -format FMT    Use output format FMT (default is legacy).

Logging options (separate multiple options with colons):

  debug, warning, profile

Output formats:

  legacy        Traditional output format, compatible with earliest
                versions of Wikiprep.
  composite     New format that consolidates most of the extracted
                data in a single large XML file.
END
}
