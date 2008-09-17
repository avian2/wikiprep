# vim:sw=2:tabstop=2:expandtab

package Wikiprep::Output::Legacy;

use warnings;
use strict;

use Wikiprep::utils qw( encodeXmlChars getLinkIds removeDuplicatesAndSelf );
use Wikiprep::templates;
use Wikiprep::interwiki;

sub new 
{
	my $class = shift;
	my $basepath = shift;
  my $inputFile = shift;

  my %params = @_;

	my $outputFile = "$basepath.hgw.xml";

  my $anchorTextFile = "$basepath.anchor_text";

  # Information about anchor texts for external linnks
  my $externalAnchorTextFile = "$basepath.external_anchors";

  my $relatedLinksFile = "$basepath.related_links";

  # Disambiguation links
  my $disambigPagesFile = "$basepath.disambig";

  # Information about nonexistent pages and IDs that were assigned to them 
  # (named "local" because assigned IDs are only unique within this dump and not
  # across Wikipedia) 
  my $localPagesFile = "$basepath.local.xml";

  # File containing the lowest local ID number (all pages with IDs larger than this
  # are local)
  my $localIDFile = "$basepath.min_local_id";

  # Information about redirects
  my $redirFile = "$basepath.redir.xml";

  # Information about template inclusion
  my $templateIncDir = "$basepath.templates";

  # Information about template inclusion
  my $interwikiDir = "$basepath.interwiki";

  my $templateIndexFile = "$templateIncDir/index";

	my $self = {};

  $self->{inputFile} = $inputFile;
  $self->{redirFile} = $redirFile;
  $self->{templateIncDir} = $templateIncDir;
  $self->{interwikiDir} = $interwikiDir;

  &Wikiprep::templates::prepare(\$templateIncDir);
  &Wikiprep::interwiki::prepare(\$interwikiDir);

  if( $params{COMPRESS} ) {
    open( $self->{outf}, "| gzip >$outputFile.gz") or 
      die "Cannot open pipe to gzip: $!: $outputFile.gz";

    open( $self->{anchorf}, "| gzip > $anchorTextFile.gz") or 
      die "Cannot open pipe to gzip: $!: $anchorTextFile.gz";

    open( $self->{exanchorf}, "| gzip > $externalAnchorTextFile.gz") or
      die "Cannot open pipe to gzip: $!: $externalAnchorTextFile.gz";
  } else {
    open( $self->{outf}, "> $outputFile") or 
      die "Cannot open $outputFile: $!";
    open( $self->{anchorf}, "> $anchorTextFile") or 
      die "Cannot open $anchorTextFile: $!";
    open( $self->{exanchorf}, "> $externalAnchorTextFile") or 
      die "Cannot open $externalAnchorTextFile: $!";
  }

  open( $self->{relatedf}, "> $relatedLinksFile") or 
    die "Cannot open $relatedLinksFile: $!";
  
  open( $self->{localf}, "> $localPagesFile") or 
    die "Cannot open $localPagesFile: $!";

  open( $self->{disambigf}, "> $disambigPagesFile") or 
    die "Cannot open $disambigPagesFile: $!";

  open( $self->{localidf}, "> $localIDFile") or 
    die "Cannot open $localIDFile: $!";

  open( $self->{tempindexf}, "> $templateIndexFile") or
    die "Cannot open $templateIndexFile: $!";

  binmode( $self->{outf},       ':utf8');
  binmode( $self->{anchorf},    ':utf8');
  binmode( $self->{exanchorf},  ':utf8');

  binmode( $self->{relatedf},   ':utf8');
  binmode( $self->{localf},     ':utf8');
  binmode( $self->{disambigf},  ':utf8');
  binmode( $self->{localidf},   ':utf8');
  binmode( $self->{tempindexf}, ':utf8');

  print {$self->{anchorf}} "# Line format: <Target page id>  <Source page id>  <Anchor location within text>  <Anchor text (up to the end of the line)>\n\n\n";
  print {$self->{relatedf}}"# Line format: <Page id>  <List of ids of related articles>\n\n\n";

  print {$self->{localf}} "<?xml version=\"1.0\" encoding=\"utf-8\"?>\n";
  print {$self->{localf}} "<pages>\n";

  print {$self->{disambigf}} "# Line format: <Disambig page id>  <Target page id (or \"undef\")> <Target anchor> ...\n\n\n";
  print {$self->{exanchorf}} "# Line format: <Source page id>  <Url>  <Anchor>\n\n\n";
  print {$self->{tempindexf}} "# Line format: <Template page id>  <Template name>\n";

	bless $self, $class;

  $self->_copyXmlFileHeader();

	return $self;
}

sub finish
{
  my $self = shift;

  print {$self->{outf}} "</mediawiki>\n";
  close($self->{outf});

  close($self->{anchorf});
  close($self->{exanchorf});

  close($self->{relatedf});

  print {$self->{localf}} "</pages>\n";
  close($self->{localf});

  close($self->{disambigf});
  close($self->{tempindexf});
}

sub lastLocalID
{
  my $self = shift;
  my ($localIDCounter) = @_;

  print {$self->{localidf}} "$localIDCounter\n";
  close( $self->{localidf} );
}

sub newLocalID
{
  my $self = shift;
  my ($id, $title) = @_;

  my $encodedTargetTitle = $title;
 	&encodeXmlChars(\$encodedTargetTitle);

  print {$self->{localf}} "<page>\n<id>", $id, "</id>\n<title>", $encodedTargetTitle, "</title>\n</page>\n";
}

# Save information about redirects into an XML-formatted file.
sub writeRedirects 
{
  my $self = shift;
  my ($refToRedir, $refToTitle2Id, $refToTemplates) = @_;

  my $fromTitle;
  my $toTitle;
  my $fromId;
  my $toId;

  open(REDIRF, "> $self->{redirFile}") or die "Cannot open $self->{redirFile}: $!";
  binmode(REDIRF, ':utf8');

  print REDIRF "<?xml version=\"1.0\" encoding=\"utf-8\"?>\n";
  print REDIRF "<redirects>\n";

  while(($fromTitle, $toTitle) = each(%$refToRedir)) {

    if ( exists( $refToTitle2Id->{$fromTitle} ) ) {
      $fromId = $refToTitle2Id->{$fromTitle};
      next if ( exists( $refToTemplates->{$fromId} ) );
    } else {
      $fromId = "unknown";
    }

    if ( exists( $refToTitle2Id->{$toTitle} ) ) {
      $toId = $refToTitle2Id->{$toTitle};
      next if ( exists( $refToTemplates->{$toId} ) );
    } else {
      $toId = "unknown";
    }

    my $encodedFromTitle = $fromTitle;
    &encodeXmlChars(\$encodedFromTitle);
    my $encodedToTitle = $toTitle;
    &encodeXmlChars(\$encodedToTitle);

    print REDIRF "<redirect>\n<from>\n<id>", $fromId, "</id>\n<title>", $encodedFromTitle, "</title>\n</from>\n<to>\n<id>", $toId, "</id>\n<title>", $encodedToTitle, "</title>\n</to>\n</redirect>\n"
  }

  print REDIRF "</redirects>\n";
	
  close(REDIRF)
}

sub newTemplate 
{
  my $self = shift;
  my ($id, $title) = @_;

  print {$self->{tempindexf}} "$id\t$title\n";
}

sub _copyXmlFileHeader 
{
  my $self = shift;

  if ($self->{inputFile} =~ /\.gz$/) {
    open(INF, "gzip -dc $self->{inputFile}|") or die "Cannot open $self->{inputFile}: $!";
  } elsif ($self->{inputFile} =~ /\.bz2$/) {
    open(INF, "bzip2 -dc $self->{inputFile}|") or die "Cannot open $self->{inputFile}: $!";
  } else {
    open(INF, "< $self->{inputFile}") or die "Cannot open $self->{inputFile}: $!";
  }

  while (<INF>) { # copy lines up to "</siteinfo>"
    if (/^<mediawiki /) {
      # The top level element - mediawiki - contains a lot of attributes (e.g., schema)
      # that are no longer applicable to the XML file after our transformation.
      # Therefore, we simply write an opening tag <mediawiki> without any attributes.
      print {$self->{outf}} "<mediawiki>\n";
    } else {
      # All other lines (up to </siteinfo>) are copied as-is
      print {$self->{outf}} $_;
    }
    last if (/<\/siteinfo>/);
  }

  close(INF); # this file will later be reopened by "Parse::MediaWikiDump"
}

sub newPage 
{
  my $self = shift;
  my ($page) = @_;

  $self->_logAnchorText($page);
  $self->_logInterwikiLinks($page);
  $self->_logTemplateIncludes($page);
  $self->_logRelatedArticles($page);
  $self->_logExternalAnchors($page);
  $self->_logDisambig($page);

  $self->_writePage($page);
}

sub _logAnchorText 
{
  my $self = shift;
  my ($page) = @_;

  # We remove the links that point from the page to itself.
  foreach my $AnchorArrayEntry (@{$page->{internalLinks}}) {
    my $targetId = $AnchorArrayEntry->{targetId};
    my $anchorText = $AnchorArrayEntry->{anchorText};
    my $linkLocation = $AnchorArrayEntry->{linkLocation};

    if (defined($targetId) and $targetId != $page->{id}) {
      $anchorText =~ s/\n/ /g;  # replace all newlines with spaces

      $anchorText =~ s/^\s*//g;  # remove leading and trainling whitespace
      $anchorText =~ s/\s*$//g;

      # make sure that something is left of anchor text after postprocessing
      #if (length($anchorText) > 0) {
      print {$self->{anchorf}} "$targetId\t$page->{id}\t$linkLocation\t$anchorText\n";
      #}
    }
  }
}

sub _logExternalAnchors
{
  my $self = shift;
  my ($page) = @_;

  foreach my $link ( @{$page->{externalLinks}} ) {
    if( defined( $link->{anchor} ) ) {
      print {$self->{exanchorf}} "$page->{id}\t$link->{url}\t$link->{anchor}\n";
    }
  }
}

sub _logInterwikiLinks 
{
  my $self = shift;
  my ($page) = @_;

  foreach my $link ( @{$page->{interwikiLinks}} ) {
    open(INTERF, ">>$self->{interwikiDir}/$link->{targetWiki}");
    binmode(INTERF, ':utf8');
    print INTERF "$page->{id}\t$link->{targetTitle}\n";
    close(INTERF);
  }
}

sub _logTemplateIncludes 
{
  my $self = shift;
  my ($page) = @_;

  my $templateIncDir = $self->{templateIncDir};

  while(my ($templateId, $log) = each(%{$page->{templates}})) {
    my $path = &Wikiprep::templates::logPath(\$templateIncDir, \$templateId);

    open(TEMPF, ">>$path") or die("$path: $!");
    binmode(TEMPF,  ':utf8');

    for my $refToParameterHash (@$log) {
      print TEMPF "Page $page->{id}\n";

      while(my ($parameter, $value) = each(%$refToParameterHash) ) {
        if($parameter !~ /^=/) {
          $value =~ s/\n/ /g;
          print TEMPF "$parameter = $value\n";
        }
      }
      print TEMPF "End\n";
    }

    close(TEMPF);
  }
}

sub _writePage
{
  my $self = shift;
  my ($page) = @_;

  my $numCategories = scalar(@{$page->{categories}});

  my @internalLinks;
  &getLinkIds(\@internalLinks, $page->{internalLinks});
  &removeDuplicatesAndSelf(\@internalLinks, $page->{id});

  my @urls;
  for my $link (@{$page->{externalLinks}}) {
    push(@urls, $link->{url});
  }

  &removeDuplicatesAndSelf(\@urls, undef);

  my $outf = $self->{outf};

  my $numLinks = scalar(@internalLinks);
  my $numUrls = scalar(@urls);

  print $outf "<page id=\"$page->{id}\" orglength=\"$page->{orgLength}\" newlength=\"$page->{newLength}\" stub=\"$page->{isStub}\" " .
             "categories=\"$numCategories\" outlinks=\"$numLinks\" urls=\"$numUrls\">\n";

  my $encodedTitle = $page->{title};
  &encodeXmlChars(\$encodedTitle);
  print $outf "<title>$encodedTitle</title>\n";

  print $outf "<categories>";
  print $outf join(" ", @{$page->{categories}});
  print $outf "</categories>\n";

  print $outf "<links>";
  print $outf join(" ", @internalLinks);
  print $outf "</links>\n";

  print $outf "<urls>\n";

  for my $url (@urls) {
    &encodeXmlChars(\$url);
    print $outf "$url\n";
  }
  print $outf "</urls>\n";

  # text has already undergone 'encodeXmlChars' in function 'postprocessText'
  print $outf "<text>\n$page->{text}\n</text>\n";

  print $outf "</page>\n";
}

sub _logRelatedArticles
{
  my $self = shift;
  my ($page) = @_;

  my $size = scalar(@{$page->{relatedArticles}});
  return if ($size == 0);

  print {$self->{relatedf}} "$page->{id}\t", join(" ", @{$page->{relatedArticles}}), "\n";
}

sub _logDisambig 
{
  my $self = shift;
	my ($page) = @_;

  return unless $page->{isDisambig};

  for my $disambigLinks (@{$page->{disambigLinks}}) {

	  print {$self->{disambigf}} $page->{id};

    for my $anchor (@$disambigLinks) {

      if( defined( $anchor->{'targetId'} ) ) {
        print {$self->{disambigf}} "\t$anchor->{'targetId'}";
      } else {
        print {$self->{disambigf}} "\tundef";
      }
      print {$self->{disambigf}} "\t$anchor->{'anchorText'}"
    }

  	print {$self->{disambigf}} "\n";
  }
}

1;
