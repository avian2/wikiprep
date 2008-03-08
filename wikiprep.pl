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

use FindBin;
use lib "$FindBin::Bin";

use images;
use nowiki;
use revision;
use languages;

my $licenseFile = "COPYING";
my $version = "2.02.tomaz.2";

if (@ARGV < 1) {
  &printUsage();
  exit 0;
}

my $file;
my $showLicense = 0;
my $showVersion = 0;
my $dontExtractUrls = 0;
my $doWriteLog = 0;

GetOptions('f=s' => \$file,
           'license' => \$showLicense,
           'version' => \$showVersion,
           'nourls' => \$dontExtractUrls,
           'log' => \$doWriteLog);

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


##### Global definitions #####

my %XmlEntities = ('&' => 'amp', '"' => 'quot', "'" => 'apos', '<' => 'lt', '>' => 'gt');

my $relatedWording_Standalone =
  qr/Main(?:\s+)article(?:s?)|Further(?:\s+)information|Related(?:\s+)article(?:s?)|Related(?:\s+)topic(?:s?)|See(?:\s+)main(?:\s+)article(?:s?)|See(?:\s+)article(?:s?)|See(?:\s+)also|For(?:\s+)(?:more|further)/i;
  ## For(?:\s+)more(?:\s+)(?:background|details)(?:\s+)on(?:\s+)this(?:\s+)topic,(?:\s+)see
my $relatedWording_Inline = qr/See[\s:]|See(?:\s+)also|For(?:\s+)(?:more|further)/i;
my $relatedWording_Section = qr/Further(?:\s+)information|See(?:\s+)also|Related(?:\s+)article(?:s?)|Related(?:\s+)topic(?:s?)/i;

my %monthToNumDays = ('January' => 31, 'February' => 29, 'March' => 31, 'April' => 30,
                      'May' => 31, 'June' => 30, 'July' => 31, 'August' => 31,
                      'September' => 30, 'October' => 31, 'November' => 30, 'December' => 31);
my %numberToMonth = (1 => 'January', 2 => 'February', 3 => 'March', 4 => 'April',
                     5 => 'May', 6 => 'June', 7 => 'July', 8 => 'August',
                     9 => 'September', 10 => 'October', 11 => 'November', 12 => 'December');

my $maxTemplateRecursionLevels = 5;
my $maxParameterRecursionLevels = 5;
my $maxTableRecursionLevels = 5;

# We use a different (and faster) way of recursively including templates than MediaWiki. In most
# cases this produces satisfactory results, however certain templates break our parser by resolving
# to meta characters like {{ and |. These templates are used as hacks around escaping issues in 
# Mediawiki and mostly concern wiki table syntax. Since we ignore content in tables we can safely
# ignore these templates.
#
# See http://meta.wikimedia.org/wiki/Template:!
my %overrideTemplates = ('Template:!' => ' ', 'Template:!!' => ' ', 'Template:!-' => ' ',
                         'Template:-!' => ' ');

##### Global variables #####

my %namespaces;
# we only process pages in these namespaces + the main namespace (which has an empty name)
my %okNamespacesForPrescanning = ('Template' => 1, 'Category' => 1, 'Image' => 1);
# we don't use templates as concepts. Image descriptions are included in the dump as normal pages.
my %okNamespacesForTransforming = ('Category' => 1, 'Image' => 1); 
my %okNamespacesForLocalPages = ('Image' => 1);

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

my ($fileBasename, $filePath, $fileSuffix) = fileparse($file, ".xml");
my $outputFile = "$filePath/$fileBasename.hgw$fileSuffix";
my $logFile = "/dev/null";
if ($doWriteLog) {
  $logFile = "$filePath/$fileBasename.log";
}
my $anchorTextFile = "$filePath/$fileBasename.anchor_text";
my $relatedLinksFile = "$filePath/$fileBasename.related_links";

# Disambiguation links
my $disambigPagesFile = "$filePath/$fileBasename.disambig";

# Information about nonexistent pages and IDs that were assigned to them 
# (named "local" because assigned IDs are only unique within this dump and not
# across Wikipedia) 
my $localPagesFile = "$filePath/$fileBasename.local.xml";

# File containing the lowest local ID number (all pages with IDs larger than this
# are local)
my $localIDFile = "$filePath/$fileBasename.min_local_id";

# Information about redirects
my $redirFile = "$filePath/$fileBasename.redir.xml";

# Information about template inclusion
my $templateIncDir = "$filePath/$fileBasename.templates";

# Information about dump and wikiprep versions
my $versionFile = "$filePath/$fileBasename.version";

# Needed for benchmarking and ETA calculation
my $totalPageCount = 0;
my $totalByteCount = 0;

&revision::writeVersion($versionFile, $file);

open(OUTF, "> $outputFile") or die "Cannot open $outputFile";
open(LOGF, "> $logFile") or die "Cannot open $logFile";
open(ANCHORF, "> $anchorTextFile") or die "Cannot open $anchorTextFile";
open(RELATEDF, "> $relatedLinksFile") or die "Cannot open $relatedLinksFile";
open(LOCALF, "> $localPagesFile") or die "Cannot open $localPagesFile: $!";
open(DISAMBIGF, "> $disambigPagesFile") or die "Cannot open $disambigPagesFile: $!";
open(LOCALIDF, "> $localIDFile") or die "Cannot open $localIDFile: $!";

binmode(STDOUT,  ':utf8');
binmode(STDERR,  ':utf8');
binmode(OUTF,    ':utf8');
binmode(LOGF,    ':utf8');
binmode(ANCHORF, ':utf8');
binmode(RELATEDF, ':utf8');
binmode(LOCALF, ':utf8');
binmode(DISAMBIGF, ':utf8');
binmode(LOCALIDF, ':utf8');

mkdir($templateIncDir);

if( opendir(TEMPD, "$templateIncDir") ) {
  my @dirContents = readdir(TEMPD);
  unlink @dirContents;
  closedir(TEMPD);
}

print ANCHORF  "# Line format: <Target page id>  <Source page id>  <Anchor location within text>  <Anchor text (up to the end of the line)>\n\n\n";
print RELATEDF "# Line format: <Page id>  <List of ids of related articles>\n\n\n";

print LOCALF "<?xml version=\"1.0\" encoding=\"utf-8\"?>\n";
print LOCALF "<pages>\n";

print DISAMBIGF  "# Line format: <Disambig page id>  <Target page id (or \"undef\")> <Target anchor> ...\n\n\n";

&copyXmlFileHeader();
&loadNamespaces();
&prescan();

print LOCALIDF "$localIDCounter\n";
close(LOCALIDF);

my $numTitles = scalar( keys(%title2id) );
print "Loaded $numTitles titles\n";
my $numRedirects = scalar( keys(%redir) );
print "Loaded $numRedirects redirects\n";
my $numTemplates = scalar( keys(%templates) );
print "Loaded $numTemplates templates\n";

&transform();
&closeXmlFile();

&writeRedirects();
&writeStatistics();
&writeCategoryHierarchy();

print LOCALF "</pages>\n";

close(LOGF);
close(ANCHORF);
close(RELATEDF);
close(LOCALF);
close(DISAMBIGF);

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

  if ( ${$page->text} =~ /(\{\{ 
                                (?:\s*)
    			                      (?:
    				                        (disambiguation)|
                                    (disambig)|
                       		          (dab)|
                       		          (hndis)|
                                    (surname)|
                       		          (geodis)|
                       		          (schooldis)|
                       		          (hospitaldis)|
                       		          (mathdab)|
                                    (numberdis)
			                          )
                                (?:\s*)
                                (?:\|.*)?
                                (?:\s*)
		                      \}\})/ix ) {
    $result = 1;
  } elsif ( $page->title =~ /\(disambiguation\)/i ) {
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
      $result = defined( $okNamespacesForLocalPages{$$refToNamespace} );
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

  &isNamespaceOk($page, \%okNamespacesForPrescanning);
}

sub isNamespaceOkForTransforming($) {
  my ($page) = @_;

  &isNamespaceOk($page, \%okNamespacesForTransforming);
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

sub isTitleOkForLocalPages(\$) {
  my ($refToPageTitle) = @_;

  my $namespaceOk = 0;

  if ($$refToPageTitle =~ /^:.*$/) {
    # Leading colon by itself implies main namespace
    $namespaceOk = 0;
  } elsif ($$refToPageTitle =~ /^([^:]*):/) {
    # colon found but not in the first position - check if it designates a known namespace
    my $prefix = $1;
    &normalizeNamespace(\$prefix);
    $namespaceOk = &isNamespaceOkForLocalPages(\$prefix);
  }

  # The case when the page title does not contain a colon at all also falls here.

  return $namespaceOk
}

sub encodeXmlChars(\$) {
  my ($refToStr) = @_;

  $$refToStr =~ s/([&"'<>])/&$XmlEntities{$1};/g;
}

sub copyXmlFileHeader() {
  open(INF, "< $file") or die "Cannot open $file: $!";
  while (<INF>) { # copy lines up to "</siteinfo>"
    if (/^<mediawiki /) {
      # The top level element - mediawiki - contains a lot of attributes (e.g., schema)
      # that are no longer applicable to the XML file after our transformation.
      # Therefore, we simply write an opening tag <mediawiki> without any attributes.
      print OUTF "<mediawiki>\n";
    } else {
      # All other lines (up to </siteinfo>) are copied as-is
      print OUTF;
    }
    last if (/<\/siteinfo>/);
  }
  close(INF); # this file will later be reopened by "Parse::MediaWikiDump"
}

sub closeXmlFile() {
  print OUTF "</mediawiki>\n";
  close(OUTF);
}

# Save information about redirects into an XML-formatted file.
sub writeRedirects() {
  my $fromTitle;
  my $toTitle;
  my $fromId;
  my $toId;

  open(REDIRF, "> $redirFile") or die "Cannot open $redirFile: $!";
  binmode(REDIRF, ':utf8');

  print REDIRF "<?xml version=\"1.0\" encoding=\"utf-8\"?>\n";
  print REDIRF "<redirects>\n";

  foreach $fromTitle ( keys(%redir) ) {
    $toTitle = $redir{$fromTitle};

    if ( exists( $title2id{$fromTitle} ) ) {
      $fromId = $title2id{$fromTitle};
    } else {
      $fromId = "unknown";
    }

    if ( exists( $title2id{$toTitle} ) ) {
      $toId = $title2id{$toTitle};
    } else {
      $toId = "unknown";
    }

    my $encodedFromTitle=$fromTitle;
    &encodeXmlChars(\$encodedFromTitle);
    my $encodedToTitle=$toTitle;
    &encodeXmlChars(\$encodedToTitle);
    

    print REDIRF "<redirect>\n<from>\n<id>", $fromId, "</id>\n<title>", $encodedFromTitle, "</title>\n</from>\n<to>\n<id>", $toId, "</id>\n<title>", $encodedToTitle, "</title>\n</to>\n</redirect>\n"

  }

  print REDIRF "</redirects>\n";
	
  close(REDIRF)
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
  # re-open the input XML file
  my $pages = Parse::MediaWikiDump::Pages->new($file);

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
  my $pages = Parse::MediaWikiDump::Pages->new($file);

  my $counter = 0;
  
  my %idexists;

  my $page;

  open(TEMPINDEX, "> $templateIncDir/index");
  binmode(TEMPINDEX,  ':utf8');

  print TEMPINDEX "# Line format: <Template page id>  <Template name>\n";

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
      print LOGF "[$timeStr] Prescanning page id=$id\n";
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
      print LOGF "Skipping page with empty title id=$id\n";
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

    if ( exists($idexists{$id}) ) {
      print LOGF "Warning: Page id=$id already encountered before!\n";
      next;
    }
    if ( exists($title2id{$title}) ) {
      # A page could have been encountered before with a different spelling.
      # Examples: &nbsp; = <C2><A0> (nonbreakable space), &szlig; = <C3><9F> (German Eszett ligature)
      print LOGF "Warning: Page title='$title' already encountered before!\n";
      next;
    }
    $idexists{$id} = 'x';
    $title2id{$title} = $id;

    if ($title =~ /^Template:/) {
      my $text = ${$page->text};

      print TEMPINDEX "$id\t$title\n";

      # We're storing template text for future inclusion, therefore,
      # remove all <noinclude> text and keep all <includeonly> text
      # (but eliminate <includeonly> tags per se).
      # However, if <onlyinclude> ... </onlyinclude> parts are present,
      # then only keep them and discard the rest of the template body.
      # This is because using <onlyinclude> on a text fragment is
      # equivalent to enclosing it in <includeonly> tags **AND**
      # enclosing all the rest of the template body in <noinclude> tags.
      # These definitions can easily span several lines, hence the "/s" modifiers.

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
        $text =~ s/<noinclude>(?:.*?)<\/noinclude>/\n/sg;
        $text =~ s/<includeonly>(.*?)<\/includeonly>/$1/sg;
      }

      $templates{$id} = $text;
    }
  }

  close(TEMPINDEX);

  my $timeStr = &getTimeAsString();
  print LOGF "[$timeStr] Prescanning complete - prescanned $counter pages\n";

  print "Total $totalPageCount pages ($totalByteCount bytes)\n";
  print LOGF "Total $totalPageCount pages ($totalByteCount bytes)\n";
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

    my $timeStr = &getTimeAsString();
    print LOGF "[$timeStr] Transforming page id=$id\n";

    if ( defined( &isRedirect($page) ) ) {
      next; # we've already loaded all redirects in the prescanning phase
    }

    if ( ! &isNamespaceOkForTransforming($page) ) {
      next; # we're only interested in pages from certain namespaces
    }

    my $title = $page->title;
    &normalizeTitle(\$title);

    # see the comment about empty titles in function 'prescan'
    if (length($title) == 0) {
      print LOGF "Skipping page with empty title id=$id\n";
      next;
    }

    my $text = ${$page->text};

    my $orgLength = length($text);  # text length BEFORE any transformations

    # The check for stub must be done BEFORE any further processing,
    # because stubs indicators are templates, and templates are substituted.
    my $isStub = 0;
    if ( $text =~ m/stub}}/i ) {
      $isStub = 1;
    }

    # Parse disambiguation pages before template substitution because disambig
    # indicators are also templates.
    if ( &isDisambiguation($page) ) {
      print LOGF "Parsing disambiguation page\n";

      &parseDisambig(\$id, \$text);
    }

    my @categories;
    my @internalLinks;
    my @urls;

    &includeTemplates(\$id, \$title, \$text);

    my @relatedArticles;
    # This function only examines the contents of '$text', but doesn't change it.
    &identifyRelatedArticles(\$text, \@relatedArticles, $id);

    # We process categories directly, because '$page->categories' ignores
    # categories inherited from included templates
    &extractCategories(\$text, \@categories, $id);

    # Categories are listed at the end of articles, and therefore may mistakenly
    # be added to the list of related articles (which often appear in the last
    # section such as "See also"). To avoid this, we explicitly remove all categories
    # from the list of related links, and only then record the list of related links
    # to the file.
    &removeElements(\@relatedArticles, \@categories);
    &recordRelatedArticles($id, \@relatedArticles);

    &images::convertGalleryToLink(\$text);
    &images::convertImagemapToLink(\$text);

    my @anchorTexts;

    &extractInternalLinks(\$text, \@internalLinks, $id, \@anchorTexts, 1, 0);

    &logAnchorText(\@anchorTexts, $id);

    if ( ! $dontExtractUrls ) {
      &extractUrls(\$text, \@urls);
    }

    &postprocessText(\$text, 1);

    my $newLength = length($text);  # text length AFTER all transformations

    &writePage($id, \$title, \$text, $orgLength, $newLength, $isStub, \@categories, \@internalLinks, \@urls);

    &updateStatistics(\@categories, \@internalLinks);

    if ($title =~ /^Category:/) {
      &updateCategoryHierarchy($id, \@categories);
    }

    my $nowTime = time;

    my $bytesPerSecond = $processedByteCount/($nowTime-$startTime);
    my $percentDone = 100.0*$processedByteCount/$totalByteCount;
    my $secondsLeft = ($totalByteCount-$processedByteCount)/$bytesPerSecond;

    my $hoursLeft = $secondsLeft/3600;

    if ( $processedPageCount % 100 == 0 ) {
      printf "At %.1f%% (%.0f bytes/s) ETA %.1f hours \r", $percentDone, $bytesPerSecond, $hoursLeft;
      STDOUT->flush();
    }
  }
  print "\n"
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

sub writePage($\$\$$$$\@\@\@) {
  my ($id, $refToTitle, $refToText, $orgLength, $newLength, $isStub,
      $refToCategories, $refToInternalLinks, $refToUrls) = @_;

  my $numCategories = scalar(@$refToCategories);
  my $numLinks = scalar(@$refToInternalLinks);
  my $numUrls = scalar(@$refToUrls);

  print OUTF "<page id=\"$id\" orglength=\"$orgLength\" newlength=\"$newLength\" stub=\"$isStub\" " .
             "categories=\"$numCategories\" outlinks=\"$numLinks\" urls=\"$numUrls\">\n";

  my $encodedTitle = $$refToTitle;
  &encodeXmlChars(\$encodedTitle);
  print OUTF "<title>$encodedTitle</title>\n";

  print OUTF "<categories>";
  print OUTF join(" ", @$refToCategories);
  print OUTF "</categories>\n";

  print OUTF "<links>";
  print OUTF join(" ", @$refToInternalLinks);
  print OUTF "</links>\n";

  print OUTF "<urls>\n";

  my $url;
  foreach $url (@$refToUrls) {
    &encodeXmlChars(\$url);
    print OUTF "$url\n";
  }
  print OUTF "</urls>\n";

  # text has already undergone 'encodeXmlChars' in function 'postprocessText'
  print OUTF "<text>\n$$refToText\n</text>\n";

  print OUTF "</page>\n";
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
      $targetTitle = undef; # double redirects are not allowed and are ignored
      print LOGF "Warning: link '$$refToTitle' caused double redirection and was ignored\n";
    } else {
      print LOGF "Link '$$refToTitle' was redirected to '$targetTitle'\n";
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
          print LOGF "Link '$$refToTitle' was ignored\n";
          $targetId = undef;
	# Assign a local ID otherwise and add the nonexistent page to %title2id hash
        } else {
          $targetId = $localIDCounter;
          $localIDCounter++;

          $title2id{$targetTitle}=$targetId;

	  my $encodedTargetTitle=$targetTitle;
	  &encodeXmlChars(\$encodedTargetTitle);

          print LOCALF "<page>\n<id>", $targetId, "</id>\n<title>", $encodedTargetTitle, "</title>\n</page>\n";

          print LOGF "Warning: link '$$refToTitle' cannot be matched to an known ID, assigning local ID\n";
        } 
    }
  } else {
    $targetId = undef;
  }

  $targetId; # return value
}

BEGIN {

my $nowikiRegex = qr/((?:<nowiki>.*?<\/nowiki>)|(?:<!--.*?-->))/;

sub includeTemplates(\$\$\$) {
  my ($refToId, $refToTitle, $refToText) = @_;

  # Using the while loop forces templates to be included recursively
  # (i.e., includes the body of templates that themselves were included
  # on the previous iteration ).
  # Template definitions can easily span several lines, hence the "/s" modifier.

  # Templates are frequently nested. Occasionally, parsing mistakes may cause template insertion
  # to enter an infinite loop, for instance when trying to instantiate Template:Country
  # {{country_{{{1}}}|{{{2}}}|{{{2}}}|size={{{size|}}}|name={{{name|}}}}}
  # which is repeatedly trying to insert template "country_", which is again resolved to
  # Template:Country. The straightforward solution of keeping track of templates that were
  # already inserted for the current article would not work, because the same template
  # may legally be used more than once, with different parameters in different parts of
  # the article. Therefore, we simply limit the number of iterations of nested template
  # inclusion.

  my $templateRecursionLevels = 0;

  # We also require that the body of a template does not contain the template opening sequence
  # (two successive opening braces - "\{\{"). We use negative lookahead to achieve this.

  # Use negative look-ahead and look-behind to make sure that we are matching agains two opening
  # braces and not three (which may be left after unsuccessful parameter substitution
  while ($templateRecursionLevels < $maxTemplateRecursionLevels) {
    my %ChunksReplaced = ();

    # Hide template invocations nested inside <nowiki> tags from the s/// operator. This prevents 
    # infinite loops if templates include an example invocation in <nowiki> tags.
    &nowiki::extractTags($nowikiRegex, $refToText, \%ChunksReplaced);

    my $r = $$refToText =~ s/(?<!\{)\{\{(?!\{)
                                (?:\s*)        # optional whitespace before the template name is ignored
                                (
                                  (?:
                                      (?!
                                          \{\{
                                      )
                                      .
                                  )*?
                                )
# OLD code and comments
#                                (?:\s*)        # optional whitespace before the template name is ignored
#                                ([^\{]*?)      # Occasionally, templates are nested,
#                                               # e.g., {{localurl:{{NAMESPACE}}:{{PAGENAME}}}}
#                                               # In order to prevent incorrect parsing, e.g.,
#                                               # "{{localurl:{{NAMESPACE}}", we require that the
#                                               # template name does not include opening braces,
#                                               # hence "[^\{]" (any char except opening brace).
# END OF OLD code and comments
                             \}\}
                            /&instantiateTemplate($1, $refToId, $refToTitle)/segx;

    &nowiki::replaceTags($refToText, \%ChunksReplaced);

    last unless ($r);

    # print LOGF "Finished with templates level $templateRecursionLevels\n";
    # print LOGF "#########\n\n";
    # print LOGF "$$refToText";
    # print LOGF "#########\n\n";
    $templateRecursionLevels++;
  }

  # Since we limit the number of levels of template recursion, we might end up with several
  # un-instantiated templates. In this case we simply eliminate them - however, we do so
  # later, in function 'postprocessText()', after extracting categories, links and URLs.
}

}

BEGIN {
  # Making variables static for the function to avoid recompilation of regular expressions
  # every time the function is called.

  my $specialSeparator = "\.pAr\.";
  my $specialSeparatorRegex = qr/$specialSeparator/;

  sub parseTemplateInvocation(\$\$\%) {
    my ($refToTemplateInvocation, $refToTemplateTitle, $refToParameterHash) = @_;

    # Template definitions (especially those with parameters) can easily span several lines,
    # hence the "/s" modifier. The template name extends up to the first pipeline symbol (if any).
    # Template parameters go after the "|" symbol.
    if ($$refToTemplateInvocation =~ /^([^|]*)\|(.*)$/sx) {
      $$refToTemplateTitle = $1;  # single out the template name itself
      my $paramsList = $2;

      # Template parameters often contain URLs, internal links, or just other useful text,
      # whereas the template serves for presenting it in some nice way.
      # Parameters are separated by "|" symbols. However, we cannot simply split the string
      # on "|" symbols, since these frequently appear inside internal links. Therefore, we split
      # on those "|" symbols that are not inside [[...]]. It's obviously sufficient to check that
      # brackets are not improperly nested on one side of "|", so we use lookahead.
      # We first replace all "|" symbols that are not inside [[...]] with a special separator that
      # we invented, which will hopefully not normally appear in the text (.pAr.).
      # Next, we use 'split' to break the string on this new separator.

      $paramsList =~ s/\|                       # split on pipeline symbol, such that
                          (?:                   # non-capturing grouper that encloses 2 options
                              (?=               #   zero-width lookahead - option #1
                                  [^\]]*$       #     there are no closing brackets up to the end
                                                #     of the string (i.e., all the characters up to
                                                #     the end of the string are not closing brackets)
                              )                 #   end of first lookahead (= end of option #1)
                              |                 #   or
                              (?=               #   another zero-width lookahead - option #2
                                  [^\]]* \[     #     the nearest opening bracket on the right is not preceded
                                                #     by a closing bracket (i.e., all the characters that
                                                #     precede it are not closing brackets
                              )                 #   end of second lookahead  (= end of option #2)
                          )                     # end of the outer grouper
                      /$specialSeparator/sxg;   # replace matching symbols with a special separator
                                                # /s means string can contain newline chars

      my @parameters = split(/$specialSeparatorRegex/, $paramsList);

      # Parameters can be either named or unnamed. In the latter case, their name is defined by their
      # ordinal position (1, 2, 3, ...).

      my $unnamedParameterCounter = 0;
      my $parameterCounter = 0;

      # It's legal for unnamed parameters to be skipped, in which case they will get default
      # values (if available) during actual instantiation. That is {{template_name|a||c}} means
      # parameter 1 gets the value 'a', parameter 2 value is not defined, and parameter 3 gets the value 'c'.
      # This case is correctly handled by function 'split', and does not require any special handling.
      my $param;
      foreach $param (@parameters) {

        # if the value does not contain a link, we can later trim whitespace
        my $doesNotContainLink = 0;
        if ($param !~ /\]\]/) {
          $doesNotContainLink = 1; 
        }

        # For parser functions we need unmodified parameters by position. For example:
        # "{{#if: true | id=xxx }}" must expand to "id=xxx". So we store raw parameter values in parameter 
        # hash. Note that the key of the hash can't be generated any other way (parameter names can't 
        # include '=' characters)
        $parameterCounter++;

        my $unexpandedParam = $param;
        if ($doesNotContainLink) {
          &trimWhitespaceBothSides(\$unexpandedParam);
        }
        $$refToParameterHash{"=${parameterCounter}="} = $unexpandedParam;

        # Spaces before or after a parameter value are normally ignored, UNLESS the parameter contains
        # a link (to prevent possible gluing the link to the following text after template substitution)

        # Parameter values may contain "=" symbols, hence the parameter name extends up to
        # the first such symbol.
        # It is legal for a parameter to be specified several times, in which case the last assignment
        # takes precedence. Example: "{{t|a|b|c|2=B}}" is equivalent to "{{t|a|B|c}}".
        # Therefore, we don't check if the parameter has been assigned a value before, because
        # anyway the last assignment should override any previous ones.
        if ($param =~ /^([^=]*)=(.*)$/s) {
          # This is a named parameter.
          # This case also handles parameter assignments like "2=xxx", where the number of an unnamed
          # parameter ("2") is specified explicitly - this is handled transparently.

          my $parameterName = $1;
          my $parameterValue = $2;

          &trimWhitespaceBothSides(\$parameterName);
          if ($doesNotContainLink) { # if the value does not contain a link, trim whitespace
            &trimWhitespaceBothSides(\$parameterValue);
          }

          $$refToParameterHash{$parameterName} = $parameterValue;
        } else {
          # this is an unnamed parameter
          $unnamedParameterCounter++;

          $$refToParameterHash{$unnamedParameterCounter} = $unexpandedParam;
        }
      }
    } else {
      # Template invocation does not contain a pipeline symbol, hence take the entire
      # invocation text as the template title.
      $$refToTemplateTitle = $$refToTemplateInvocation;
    }
  }

} # end of BEGIN block


sub instantiateTemplate($\$\$) {
  my ($templateInvocation, $refToId, $refToTopPageTitle) = @_;

  my $result = "";

  print LOGF "Instantiating template=$templateInvocation\n";

  my $templateTitle;
  my %templateParams;
  &parseTemplateInvocation(\$templateInvocation, \$templateTitle, \%templateParams);

  &includeParserFunction(\$templateTitle, \%templateParams, $refToTopPageTitle, \$result);

  # If this wasn't a parser function call, try to include a template.
  if ( length($result) == 0 ) {
    &computeFullyQualifiedTemplateTitle(\$templateTitle);

    my $overrideResult = $overrideTemplates{$templateTitle};
    if(defined $overrideResult) {
      print LOGF "Overriding template $templateTitle\n";
      return $overrideResult;
    }

    &includeTemplateText(\$templateTitle, \%templateParams, $refToId, \$result);
  }

  $result;  # return value
}

sub includeParserFunction(\$\%\$\$) {
  my ($refToTemplateTitle, $refToParameterHash, $refToTopPageTitle, $refToResult) = @_;

  # Parser functions have the same syntax as templates, except their names start with a hash
  # and end with a colon. Everything after the first colon is the first argument.
  # http://meta.wikimedia.org/wiki/Help:ParserFunctions

  if ( $$refToTemplateTitle =~ /^\#([a-z]+):\s*(.*?)\s*$/ ) {
    my $functionName=$1;
    $$refToParameterHash{'=0='}=$2;

    print LOGF "Evaluating parser function #$functionName\n";

    if ( $functionName eq 'if' ) {

      my $valueIfTrue = $$refToParameterHash{'=1='};
      my $valueIfFalse = $$refToParameterHash{'=2='};

      # print LOGF "If condition: $2\n";
      # if ( defined($valueIfTrue) ) {
      #   print LOGF "If true: $valueIfTrue\n";
      # }
      # if ( defined($valueIfFalse) ) {
      #   print LOGF "If false: $valueIfFalse\n";
      # }

      if ( length($$refToParameterHash{'=0='}) > 0 ) {
        # The {{#if:}} function is an if-then-else construct. The applied condition is 
        # "The condition string is non-empty". 

        if ( defined($valueIfTrue) && ( length($valueIfTrue) > 0 ) ) {
          $$refToResult = $valueIfTrue;
        } else {
          $$refToResult = " ";
        }
      } else {
        if ( defined($valueIfFalse) && ( length($valueIfFalse) > 0 ) ) {
          $$refToResult = $valueIfFalse;
        } else {
          $$refToResult = " ";
        }
      }
    } elsif ( $functionName eq 'ifeq' ) {

      my $valueIfTrue = $$refToParameterHash{'=2='};
      my $valueIfFalse = $$refToParameterHash{'=3='};

      my $lvalue = $$refToParameterHash{'=0='};
      my $rvalue = $$refToParameterHash{'=1='};

      # lvalue is always defined
      if ( defined($rvalue) and ($lvalue eq $rvalue) ) {
        # The {{#ifeq:}} function is an if-then-else construct. The applied condition is 
        # "is rvalue equal to lvalue". Note that this does only string comparison while MediaWiki
        # implementation also supports numerical comparissons.

        if ( defined($valueIfTrue) && ( length($valueIfTrue) > 0 ) ) {
          $$refToResult = $valueIfTrue;
        } else {
          $$refToResult = " ";
        }
      } else {
        if ( defined($valueIfFalse) && ( length($valueIfFalse) > 0 ) ) {
          $$refToResult = $valueIfFalse;
        } else {
          $$refToResult = " ";
        }
      }
    } elsif ( $functionName eq 'language' ) {
      # {{#language: code}} gives the language name of selected RFC 3066 language codes, 
      # otherwise it returns the input value as is.

      my $code = $$refToParameterHash{'=0='};

      $$refToResult = &languages::languageName($code);
    } else {

      print LOGF "Function #$functionName not supported\n";

      # Unknown function -- fall back by inserting first argument, if available. This seems
      # to be the most sensible alternative in most cases (for example in #time and #date)

      if ( exists($$refToParameterHash{'1'}) && ( length($$refToParameterHash{'1'}) > 0 ) ) {
        $$refToResult = $$refToParameterHash{'1'};
      } else {
        $$refToResult = " ";
      }
    }

    # print LOGF "Function returned: $$refToResult\n";

  } elsif ( $$refToTemplateTitle =~ /^urlencode:\s*(.*)/ ) {
    # This function is used in some pages to construct links
    # http://meta.wikimedia.org/wiki/Help:URL

    print LOGF "URL encoding string $1\n";

    $$refToResult = $1;
    $$refToResult =~ s/([^A-Za-z0-9])/sprintf("%%%02X", ord($1))/seg;
  } elsif ( $$refToTemplateTitle eq "PAGENAME" ) {
    $$refToResult = $$refToTopPageTitle;
  }
}

sub logTemplateInclude(\$\$\%) {
  my ($refToTemplateId, $refToPageId, $refToParameterHash) = @_;

  open(TEMPF, ">>$templateIncDir/$$refToTemplateId");
  binmode(TEMPF,  ':utf8');

  print TEMPF "Page $$refToPageId\n";

  foreach my $parameter ( keys(%$refToParameterHash) ) {
    if($parameter !~ /^=/) {
      my $value = $$refToParameterHash{$parameter};
      print TEMPF "$parameter = $value\n";
    }
  }
  print TEMPF "End\n";

  close(TEMPF);
}

sub includeTemplateText(\$\%\$\$) {
  my ($refToTemplateTitle, $refToParameterHash, $refToId, $refToResult) = @_;

  &normalizeTitle($refToTemplateTitle);
  my $includedPageId = &resolveLink($refToTemplateTitle);

  if ( defined($includedPageId) && exists($templates{$includedPageId}) ) {
    # OK, perform the actual inclusion with parameter substitution

    &logTemplateInclude(\$includedPageId, $refToId, $refToParameterHash);

    $$refToResult = $templates{$includedPageId};

    # Perform parameter substitution
    # A parameter call ( {{{...}}} ) may span over a newline, hence the /s modifier

    # Parameters may be nested (see comments below), hence we do the substitution iteratively
    # in a while loop. We also limit the maximum number of iterations to avoid too long or
    # even endless loops (in case of malformed input).
    my $parameterRecursionLevels = 0;

    # We also require that the body of a parameter does not contain the parameter opening sequence
    # (three successive opening braces - "\{\{\{"). We use negative lookahead to achieve this.
    while ( ($parameterRecursionLevels < $maxParameterRecursionLevels) &&
            $$refToResult =~ s/\{\{\{
                                (
                                  (?:
                                      (?!
                                          \{\{\{
                                      )
                                      .
                                  )*?
                                )

# OLD code and comments
#                                      ([^\{]*?)      # Occasionally, parameters are nested because
#                                                     # they are dependent on other parameters,
#                                                     # e.g., {{{Author|{{{PublishYear|}}}}}}
#                                                     # (here, the default value for 'Author' is
#                                                     # dependent on 'PublishYear').
#                                                     # In order to prevent incorrect parsing, e.g.,
#                                                     # "{{{Author|{{{PublishYear|}}}", we require that the
#                                                     # parameter name does not include opening braces,
#                                                     # hence "[^\{]" (any char except opening brace).
# END OF OLD code and comments
                               \}\}\}
                              /&substituteParameter($1, $refToParameterHash)/segx
          ) {
      $parameterRecursionLevels++;
    }
  } else {
    # The page being included cannot be identified - perhaps we skipped it (because currently
    # we only allow for inclusion of pages in the Template namespace), or perhaps it's
    # a variable name like {{NUMBEROFARTICLES}}. Just remove this inclusion directive and
    # replace it with a space
    print LOGF "Template '$$refToTemplateTitle' is not available for inclusion\n";
    $$refToResult = " ";
  }
}

sub substituteParameter($\%) {
  my ($parameter, $refToParameterHash) = @_;

  my $result;

  if ($parameter =~ /^([^|]*)\|(.*)$/) {
    # This parameter has a default value
    my $paramName = $1;
    my $defaultValue = $2;

    if ( defined($$refToParameterHash{$paramName}) ) {
      $result = $$refToParameterHash{$paramName};  # use parameter value specified in template invocation
    } else { # use the default value
      $result = $defaultValue;
    }
  } else {
    # parameter without a default value

    if ( defined($$refToParameterHash{$parameter}) ) {
      $result = $$refToParameterHash{$parameter};  # use parameter value specified in template invocation
    } else {
      # Parameter not specified in template invocation and does not have a default value -
      # do not perform substitution and keep the parameter in 3 braces
      # (these are Wiki rules for templates, see  http://meta.wikimedia.org/wiki/Help:Template ).

      # $result = "{{{$parameter}}}";

      # MediaWiki syntax indeed says that unspecified parameters should remain unexpanded, however in
      # practice we get a lot less noise in the output if we expand them to zero-length strings.
      $result = "";
    }
  }

  # Surplus parameters - i.e., those assigned values in template invocation but not used
  # in the template body - are simply ignored.

  $result;  # return value
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
    $$refToTemplateTitle = "Template:$$refToTemplateTitle";
  }
}

sub extractCategories(\$\@$) {
  my ($refToText, $refToCategoriesArray, $id) = @_;

  # Remember that namespace names are case-insensitive, hence we're matching with "/i".
  # The first parameter to 'collectCategory' is passed by value rather than by reference,
  # because it might be dangerous to pass a reference to $1 in case it might get modified
  # (with unclear consequences).
  $$refToText =~ s/\[\[(?:\s*)(Category:.*?)\]\]/&collectCategory($1, $refToCategoriesArray)/ieg;

  # We don't accumulate categories directly in a hash table, since this would not preserve
  # their original order of appearance.
  &removeDuplicatesAndSelf($refToCategoriesArray, $id);
}

sub collectCategory($\@) {
  my ($catName, $refToCategoriesArray) = @_;

  if ($catName =~ /^(.*)\|/) {
    # Some categories contain a sort key, e.g., [[Category:Whatever|*]] or [[Category:Whatever| ]]
    # In such a case, take only the category name itself.
    $catName = $1;
  }

  &normalizeTitle(\$catName);

  my $catId = &resolveLink(\$catName);
  if ( defined($catId) ) {
    push(@$refToCategoriesArray, $catId);
  } else {
    print LOGF "Warning: unknown category '$catName'\n";
  }

  # The return value is just a space, because we remove categories from the text
  # after we collected them
  " ";
}

sub extractInternalLinks(\$\@$\@$$) {
  my ($refToText, $refToInternalLinksArray, $id,
      $refToAnchorTextArray, $whetherToRemoveDuplicates, $logUnknownLinks ) = @_;

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

  1 while ( $$refToText =~ s/
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
                            /&collectInternalLink($1, $2, $3, $refToInternalLinksArray, 
                                                  $refToAnchorTextArray,
                                                  $-[0], $logUnknownLinks)/segx
          );

  if ($whetherToRemoveDuplicates) {
    &removeDuplicatesAndSelf($refToInternalLinksArray, $id);
  }

}

sub logAnchorText(\@$) {
  my ($refToAnchorTextsArray, $curPageId) = @_;

  # Remember that we use a hash table to associate anchor text with target page ids.
  # Therefore, if the current page has several links to another page (it happens), then we only
  # keep the anchor text of the last one (and override the previous ones) - we can live with it.
  # Consequently, we do not need to remove duplicates as there are none.
  # However, we still remove the links that point from the page to itself.
  my $targetId;
  my $anchorText;
  my $AnchorArrayEntry;
  my $linkLocation;

  foreach $AnchorArrayEntry (@$refToAnchorTextsArray) {
    $targetId = $$AnchorArrayEntry{targetId};
    $anchorText = $$AnchorArrayEntry{anchorText};
    $linkLocation = $$AnchorArrayEntry{linkLocation};

    if ($targetId != $curPageId) {
      &postprocessText(\$anchorText, 0); # anchor text doesn't need escaping of XML characters,
                                         # hence the second function parameter is 0
      $anchorText =~ s/\n/ /g;  # replace all newlines with spaces

      $anchorText =~ s/^\s*//g;  # remove leading and trainling whitespace
      $anchorText =~ s/\s*$//g;

      # make sure that something is left of anchor text after postprocessing
      #if (length($anchorText) > 0) {
      print ANCHORF "$targetId\t$curPageId\t$linkLocation\t$anchorText\n";
      #}
    }
  }
}

sub collectInternalLink($$$\@\@$$) {
  my ($prefix, $link, $suffix, $refToInternalLinksArray, $refToAnchorTextArray, 
      $linkLocation, $logUnknownLinks) = @_;

  my $originalLink = $link;
  my $result = "";

  # strip leading whitespace, if any
  $link =~ s/^\s*//;

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
  if ($link =~ /^
                   :        # colon at the beginnning of the link name
                   (.*)     # the rest of the link text
                $
               /sx) {
    # just strip this initial colon (as well as any whitespace preceding it)
    $link = $1;
  }

  # Alternative text may be available after the pipeline symbol.
  # If the pipeline symbol is only used for masking parts of
  # the link name for presentation, we still consider that the author of the page
  # deemed the resulting text important, hence we always set this variable when
  # the pipeline symbol is present.
  my $alternativeTextAvailable = 0;

  my $isImageLink = 0;
  if ($link =~ /^Image:/) {
    $isImageLink = 1;
  }

  # First extract everything before the first pipeline symbol.
  if ($link =~ /^([^|]*)(\|.*)$/s) {
    $link = $1;
    $result = $2;

    if ($isImageLink) {
      # Image links have to parsed separately, because anchors can contain parameters (size, type, etc.)
      # which we exclude in a separate function.

      $result = &images::parseImageParameters($result);
      $alternativeTextAvailable = 1;
    } else {
      # Extract everything after the last pipeline symbol. Normal pages shouldn't have more than one
      # pipeline symbol, but remove extra pipes in case of broken or unknown new markup. Discard
      # all text before the last pipeline.
      if ($result =~ /^(.*)\|([^|]*)$/s) {
        $result = $2;
      }

      $alternativeTextAvailable = 1; # pipeline found, see comment above
    }

    if (length($result) == 0) {
      if ($isImageLink) {
        $alternativeTextAvailable = 0;
      } else {
        if ($link !~ /\#/) {
          # If the "|" symbol is not followed by some text, then it masks the namespace
          # as well as any text in parentheses at the end of the link title.
          # However, pipeline masking is only invoked if the link does not contain an anchor,
          # hence the additional condition in the 'if' statement.
          &performPipelineMasking(\$link, \$result);
        } else {
          # If the link contains an anchor, then masking is not invoked, and we take the entire link
          $result = $link;
        }
      }
    }  
  } else {
    if ($isImageLink) {
      # Nothing is displayed for images without anchors
      $result = "";
    } else {
      # the link text does not contain the pipeline, so take it as-is
      $result = $link;
    }
  }

  if ($link =~ /^(.*)\#(.*)$/s) {
    # The link contains an anchor, so adjust the link to point to the page as a whole.
    $link = $1;
    my $anchor = $2;
    # Check if the link points to an anchor on the current page, and if so - ignore it.
    if (length($link) == 0 && ! $alternativeTextAvailable) {
      # This is indeed a link pointing to an anchor on the current page.
      # The link is thus cleared, so that it will not be resolved and collected later.
      # For anchors to the same page, discard the leading '#' symbol, and take
      # the rest as the text - but only if no alternative text was provided for this link.
      $result = $anchor;
    }
  }

  # Now collect the link, or links if the original link is in the date format
  # and specifies both day and year. In the latter case, the function for date
  # normalization may also modify the link text ($result), and may collect more
  # than one link (one for the day, another one for the year).
  my $dateRecognized = 0;

  # Alternative text (specified after pipeline) blocks normalization of dates.
  # We also perform a quick check - if the link does not start with a digit,
  # then it surely does not contain a date
  if ( ($link =~ /^\d/) && (! $alternativeTextAvailable)) {
    $dateRecognized = &normalizeDates(\$link, \$result, $refToInternalLinksArray, $refToAnchorTextArray, $linkLocation);
  }

  # If a date (either day or day + year) was recognized, then no further processing is necessary
  if (! $dateRecognized) {
    &normalizeTitle(\$link);

    my $targetId = &resolveAndCollectInternalLink(\$link, $refToInternalLinksArray);

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
      print LOGF "Discarding text for link '$originalLink'\n";
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

    if ( defined($refToAnchorTextArray) ) {
      if ( defined($targetId) ) {
        push(@$refToAnchorTextArray, { targetId => "$targetId", anchorText => "$result", 
                                       linkLocation => "$linkLocation" });
      } elsif ($logUnknownLinks) {
        push(@$refToAnchorTextArray, { targetId => "undef", anchorText => "$result", 
                                       linkLocation => "$linkLocation" });
      }
    }

  }

  $result;  #return value
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

sub resolveAndCollectInternalLink(\$\@) {
  my ($refToLink, $refToInternalLinksArray) = @_;

  my $targetId = &resolveLink($refToLink);
  if ( defined($targetId) ) {
    if ( ! exists($templates{$targetId}) ) { 
      push(@$refToInternalLinksArray, $targetId);
    } else {
      print LOGF "Ignoring link to a template '$$refToLink'\n";
      $targetId = undef;
    }
  } else {
    # Some cases in this category that obviously won't be resolved to legal ids:
    # - Links to namespaces that we don't currently handle
    #   (other than those for which 'isNamespaceOK' returns true);
    #   media and sound files fall in this category
    # - Links to other languages, e.g., [[de:...]]
    # - Links to other Wiki projects, e.g., [[Wiktionary:...]]
    print LOGF "Warning: unknown link '$$refToLink'\n";
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
sub normalizeDates(\$\$\@\%) {
  my ($refToLink, $refToResultText, $refToInternalLinksArray, $refToAnchorTextArray, $linkLocation) = @_;

  my $dateRecognized = 0;

  if ($$refToLink =~ /^(\d\d)\s*([A-Za-z]+)$/) {
    my $day = $1;
    my $month = ucfirst(lc($2));

    if ( defined($monthToNumDays{$month}) &&
         1 <= $day && $day <= $monthToNumDays{$month} ) {
      $dateRecognized = 1;

      $$refToLink = "$month $day";
      $$refToResultText = "$month $day";

      my $targetId = &resolveAndCollectInternalLink($refToLink, $refToInternalLinksArray);
      if ( defined($targetId) && defined($refToAnchorTextArray) ) {
        push(@$refToAnchorTextArray, { targetId => "$targetId", anchorText => "$$refToResultText",
                                       linkLocation => "$linkLocation" });
      }
    } else {
      # this doesn't look like a valid date, leave as-is
    }
  } elsif ($$refToLink =~ /^(\d\d)\-(\d\d)$/) {
    my $monthNum = int($1);
    my $day = $2;

    if ( defined($numberToMonth{$monthNum}) ) {
      my $month = $numberToMonth{$monthNum};
      if (1 <= $day && $day <= $monthToNumDays{$month}) {
        $dateRecognized = 1;

        $$refToLink = "$month $day";
        # we add a leading space, to separate the preceding year ("[[1969]]-" in the example")
        # from the day that we're creating
        $$refToResultText = " $month $day";

        my $targetId = &resolveAndCollectInternalLink($refToLink, $refToInternalLinksArray);
        if ( defined($targetId) && defined($refToAnchorTextArray) ) {
            push(@$refToAnchorTextArray, { targetId => "$targetId", anchorText => "$$refToResultText",
                                           linkLocation => "$linkLocation" });
        }
      } else {
        # this doesn't look like a valid date, leave as-is
      }
    } else {
      # this doesn't look like a valid date, leave as-is
    }
  } elsif ($$refToLink =~ /^(\d\d\d\d)\-(\d\d)\-(\d\d)$/) {
    my $year = $1;
    my $monthNum = int($2);
    my $day = $3;

    if ( defined($numberToMonth{$monthNum}) ) {
      my $month = $numberToMonth{$monthNum};
      if (1 <= $day && $day <= $monthToNumDays{$month}) {
        $dateRecognized = 1;

        $$refToLink = "$month $day";
        # the link text is combined from the day and the year
        $$refToResultText = "$month $day, $year";

        my $targetId;

        # collect the link for the day
        $targetId = &resolveAndCollectInternalLink($refToLink, $refToInternalLinksArray);
        if ( defined($targetId) && defined($refToAnchorTextArray) ) {
            push(@$refToAnchorTextArray, { targetId => "$targetId", anchorText => "$$refToLink",
                                           linkLocation => "$linkLocation" });
        }

        # collect the link for the year
        $targetId = &resolveAndCollectInternalLink(\$year, $refToInternalLinksArray);
        if ( defined($targetId) && defined($refToAnchorTextArray) ) {
            push(@$refToAnchorTextArray, { targetId => "$targetId", anchorText => "$year",
                                           linkLocation => "$linkLocation" });
        }
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
  # The URL protocol (e.g., http) matched here may be in either case, hence we use the /i modifier.
  my $urlProtocols = qr/http:\/\/|https:\/\/|telnet:\/\/|gopher:\/\/|file:\/\/|wais:\/\/|ftp:\/\/|mailto:|news:/i;
  # A URL terminator may be either one of a list of characters OR end of string (that is, '$').
  # This last part is necessary to handle URLs at the very end of a string when there is no "\n"
  # or any other subsequent character.
  my $urlTerminator = qr/[\[\]\{\}\s\n\|\"<>]|$/;

  my $urlSequence1 = qr/\[(?:\s*)($urlProtocols(?:[^\[\]]*))\]/;
  my $urlSequence2 = qr/($urlProtocols(?:.*?))$urlTerminator/;

  sub extractUrls(\$\@) {
    my ($refToText, $refToUrlsArray) = @_;

    # First we handle the case of URLs enclosed in single brackets, with or without the description,
    # and with optional leading and/or trailing whitespace
    # Examples: [http://www.cnn.com], [ http://www.cnn.com  ], [http://www.cnn.com  CNN Web site]
    $$refToText =~ s/$urlSequence1/&collectUrlFromBrackets($1, $refToUrlsArray)/eg;

    # Now we handle standalone URLs (those not enclosed in brackets)
    # The $urlTemrinator is matched via positive lookahead (?=...) in order not to remove
    # the terminator symbol itself, but rather only the URL.
    $$refToText =~ s/$urlSequence2/&collectStandaloneUrl($1, $refToUrlsArray)/eg;

    &removeDuplicatesAndSelf($refToUrlsArray, undef);
  }

  sub collectUrlFromBrackets($\@) {
    my ($url, $refToUrlsArray) = @_;

    my $text;
    # Assumption: leading whitespace has already been stripped
    if ( $url =~ /^($urlProtocols(?:.*?))($urlTerminator(?:.*))$/ ) { # description available
      push(@$refToUrlsArray, $1);
      $text = $2;
    } else { # no description
      push(@$refToUrlsArray, $url);
      $text = " ";
    }

    $text;  # return value
  }

  sub collectStandaloneUrl($\@) {
    my ($url, $refToUrlsArray) = @_;

    push(@$refToUrlsArray, $url); # collect the URL as-is

    " "; # return value - replace the URL with a space
  }
}

sub parseDisambig(\$\$) {
	my ($refToId, $refToText) = @_;

	my @lines = split(/\n/, $$refToText);

	for my $line (@lines) {
		if ( $line =~ /^\s*(?:
					                (\*\*)|
					                (\#\#)|
                          (\:\#)|
                          (\:\*)|
                          (\#)|
                          (\*)
                        )/ix ) {

	    my @disambigLinks;
      my @anchorTexts;

			&extractInternalLinks(\$line, \@disambigLinks, $$refToId, \@anchorTexts, 0, 1);

			&writeDisambig($refToId, \@anchorTexts);
		}
	}
}

sub writeDisambig(\$\@) {
	my ($refToDisambigId, $refToAnchorTextArray) = @_;

	print DISAMBIGF "$$refToDisambigId";

  for my $anchor (@$refToAnchorTextArray) {
    print DISAMBIGF "\t$$anchor{'targetId'}\t$$anchor{'anchorText'}"
  }

	print DISAMBIGF "\n";
}

sub postprocessText(\$$) {
  my ($refToText, $whetherToEncodeXmlChars) = @_;

  # Eliminate all <includeonly> and <onlyinclude> fragments, because this text
  # will not be included anywhere, as we already handled all inclusion directives
  # in function 'includeTemplates'.
  # This block can easily span several lines, hence the "/s" modifier.
  $$refToText =~ s/<includeonly>(.*?)<\/includeonly>/ /sg;
  $$refToText =~ s/<onlyinclude>(.*?)<\/onlyinclude>/ /sg;

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

  # Remove comments (<!-- ... -->) from the text. This must be performed before removing other tags,
  # because some comments appear inside other tags (e.g. "<span <!-- comment --> class=...>"). They 
  # can easily span several lines, so we use the "/s" modifier.
  $$refToText =~ s/<!--(?:.*?)-->/ /sg;

  # Remove any other <...> tags - but keep the text they enclose
  # (the tags are replaced with spaces to prevent adjacent pieces of text
  # from being glued together).
  $$refToText =~ s/<(?:.*?)>/ /sg;

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
  $$refToText =~ s/(?:\s*)\n(?:\s*)\n(?:\s*)/\n\n/g;

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
                   ((?:\#?)(?:\w+))  # optional '#' sign (as in &#945;), followed by
                                     # an uninterrupted sequence of letters and/or digits
                   ;                 # the entity ends with a semicolon
                  }{&logReplacedXmlEntity($1)}egx;   # entities are replaced with a space

  if ($whetherToEncodeXmlChars) {
    # encode text for XML
    &encodeXmlChars($refToText);
  }

  # NOTE that the following operations introduce XML tags, so they must appear
  # after the original text underwent character encoding with 'encodeXmlChars' !!

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

  print LOGF "ENTITY: &$xmlEntity;\n";

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

# If specified, 'elementToRemove' contains an element that needs to be removed as well.
# For links, this ensures that a page does not link to itself. For categories, this
# ensures that a page is not categorized to itself. This parameter is obviously
# irrelevant for filtering URLs.
# 'elementToRemove' must be a numeric value (not string), since we're testing it with '==' (not 'eq')
sub removeDuplicatesAndSelf(\@$) {
  my ($refToArray, $elementToRemove) = @_;

  my %seen = ();
  my @uniq;

  my $item;
  foreach $item (@$refToArray) {
    if ( defined($elementToRemove) && ($item == $elementToRemove) ) {
      printf LOGF "Warning: current page links or categorizes to itself - " .
                  "link discarded ($elementToRemove)\n";
      next;
    }
    push(@uniq, $item) unless $seen{$item}++;
  }

  # overwrite the original array with the new one that does not contain duplicates
  @$refToArray = @uniq;
}

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

sub trimWhitespaceBothSides(\$) {
    my ($stringRef) = @_;

    # remove leading whitespace
    $$stringRef =~ s/^\s*//;
    # remove trailing whitespace
    $$stringRef =~ s/\s*$//;
}

# There are 3 kinds of related links that we look for:
# 1) Standalone (usually, at the beginning of the article or a section of it)
#    Ex: Main articles: ...
# 2) Inlined - text in parentheses inside the body of the article
#    Ex: medicine (see also: [[Health]])
# 3) Dedicated section
#    Ex: == See also ==
#
# In all calls to 'extractInternalLinks':
# - The penultimate argument is 0, since we don't need to log anchor text here.
#   Anchor text will be handled when we analyze all the internal links in
#   the entire article (and not just look for related links).
# - The last argument is 0 in order not to remove duplicates on every invocation
#   of 'extractInternalLinks'. This is because duplicates in related links are
#   not very common, but performing duplicate removal each time is expensive.
#   Instead, we remove duplicates once at the very end.
sub identifyRelatedArticles(\$\@$) {
  my ($refToText, $refToRelatedArticles, $id) = @_;

  # We split the text into a set of lines. This also creates a copy of the original text -
  # this is important, since the function 'extractInternalLinks' modifies its argument,
  # so we'd better use it on a copy of the real article body.
  my @text = split("\n", $$refToText);
  my $line;

  # Standalone
  foreach $line (@text) {
    # We require that stanalone designators occur at the beginning of the line
    # (after at most a few characters, such as a whitespace or a colon),
    # and not just anywhere in the line. Otherwise, we would collect as related
    # those links that just happen to occur in the same line with an unrelated
    # string that represents a standalone designator.
    if ($line =~ /^(?:.{0,5})(${relatedWording_Standalone}.*)$/) {
      my $str = $1; # We extract links from the rest of the line
      print LOGF "Related(S): $id => $str\n";
      &extractInternalLinks(\$str, $refToRelatedArticles, $id, undef, 0, 0);
      print LOGF "Related(S): $id ==> @$refToRelatedArticles\n";
    }
  }

  # Inlined (in parentheses)
  foreach $line (@text) {
    while ($line =~ /\((?:\s*)(${relatedWording_Inline}.*?)\)/g) {
      my $str = $1;
      print LOGF "Related(I): $id => $str\n";
      &extractInternalLinks(\$str, $refToRelatedArticles, $id, undef, 0, 0);
      print LOGF "Related(I): $id ==> @$refToRelatedArticles\n";
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
        print LOGF "Related(N): $id => $line\n";
        # 'extractInternalLinks' may mofidy its argument ('$line'), but it's OK
        # as we do not do any further processing to '$line' or '@text'
        &extractInternalLinks(\$line, $refToRelatedArticles, $id, undef, 0, 0);
        print LOGF "Related(N): $id ==> @$refToRelatedArticles\n";
      }
    } else { # we haven't yet found the related section
      if ($line =~ /==(.*?)==/) { # found some section header - let's check it
        my $sectionHeader = $1;
        if ($sectionHeader =~ /$relatedWording_Section/) {
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

  &removeDuplicatesAndSelf($refToRelatedArticles, $id);
}

sub recordRelatedArticles($\@) {
  my ($id, $refToRelatedArticles) = @_;

  my $size = scalar(@$refToRelatedArticles);
  return if ($size == 0);

  print RELATEDF "$id\t", join(" ", @$refToRelatedArticles), "\n";
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
       e.g., $0 -f pages_articles.xml

Available options:
  -nourls        Don't extract external links (URLs) from pages. 
                 Reduces run-time by approximately one half.
  -log           Write a large log file with debug information.
                 Log can get approximately 3-4 times larger than
                 the XML dump.
END
}
