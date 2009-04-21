# vim:sw=2:tabstop=2:expandtab

package Wikiprep::Output::Legacy;

use warnings;
use strict;

use File::Path;

use Wikiprep::utils qw( encodeXmlChars getLinkIds removeDuplicatesAndSelf 
                        openOutputFile outputFilename openInputFile );

sub new {
	my $class = shift;

  my ($inputFile, %options) = @_;

  my $self = {
               inputFile => $inputFile,
               part => $options{PART},
               templateIncDir => &outputFilename($inputFile, ".templates", %options, COMPRESS => 0) 
             };

  &_prepareTemplateIncDir(\$self->{templateIncDir});

  if($options{PRESCAN}) {
    $self->{tempindexf} = IO::File->new("> " . $self->{templateIncDir} . "/index") or die;
    $self->{tempindexf}->binmode(":utf8");

    print {$self->{tempindexf}} "# Line format: <Template page id>  <Template name>\n";
  } else {
    $self->{outf}      = openOutputFile($inputFile, ".hgw.xml", %options);
    $self->{anchorf}   = openOutputFile($inputFile, ".anchor_text", %options);
    $self->{exanchorf} = openOutputFile($inputFile, ".external_anchors", %options);
    $self->{relatedf}  = openOutputFile($inputFile, ".related_links", %options, COMPRESS => 0);
    $self->{disambigf} = openOutputFile($inputFile, ".disambig", %options, COMPRESS => 0);

    &_copyXmlFileHeader($self);
    print {$self->{anchorf}} "# Line format: <Target page id>  <Source page id>  <Anchor location within text>  <Anchor text (up to the end of the line)>\n\n\n";
    print {$self->{relatedf}}"# Line format: <Page id>  <List of ids of related articles>\n\n\n";
    print {$self->{disambigf}} "# Line format: <Disambig page id>  <Target page id (or \"undef\")> <Target anchor> ...\n\n\n";
    print {$self->{exanchorf}} "# Line format: <Source page id>  <Url>  <Anchor>\n\n\n";
  }

	bless $self, $class;
	return $self;
}

sub finish
{
  my $self = shift;

  print {$self->{outf}} "</mediawiki>\n" if $self->{outf};

  while( my ($name, $value) = each(%$self) ) {
    $value->close if( $name =~ /f$/ );
  }
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

  my $fh = &openOutputFile($self->{inputFile}, ".redir.xml", PART => $self->{part});

  print $fh "<?xml version=\"1.0\" encoding=\"utf-8\"?>\n";
  print $fh "<redirects>\n";

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

    print $fh "<redirect>\n<from>\n<id>", $fromId, "</id>\n<title>", $encodedFromTitle, "</title>\n</from>\n<to>\n<id>", $toId, "</id>\n<title>", $encodedToTitle, "</title>\n</to>\n</redirect>\n"
  }

  print $fh "</redirects>\n";
	
  close($fh);
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

  my $fh = &openInputFile($self->{inputFile});

  while (<$fh>) { 
    # copy lines up to "</siteinfo>"
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

  # this file will later be reopened by "Parse::MediaWikiDump"
  close($fh);
}

sub newPage 
{
  my $self = shift;
  my ($page) = @_;

  $self->_logAnchorText($page);
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

sub _logTemplateIncludes 
{
  my $self = shift;
  my ($page) = @_;

  my $templateIncDir = $self->{templateIncDir};

  while(my ($templateId, $log) = each(%{$page->{templates}})) {
    my $path = &_templateLogPath(\$templateIncDir, \$templateId);

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
      my $anchorText = $anchor->{'anchorText'};
      $anchorText =~ s/\t/ /g;
      print {$self->{disambigf}} "\t$anchorText"
    }

  	print {$self->{disambigf}} "\n";
  }
}

sub _prepareTemplateIncDir(\$) {
  my ($refToTemplateIncDir) = @_;

  mkdir($$refToTemplateIncDir);

  my $n = 1;
  do {
    my $path = "$$refToTemplateIncDir/$n";
    if( $$refToTemplateIncDir and -d $path ) {
      File::Path::rmtree($path, 0, 0);
    }
    mkdir("$$refToTemplateIncDir/$n");
    $n++;
  } while($n < 10);
}

sub _templateLogPath(\$\$) {
  my ($refToTemplateIncDir, $refToTemplateId) = @_;

  my $prefix = substr($$refToTemplateId, 0, 1);

  return "$$refToTemplateIncDir/$prefix/$$refToTemplateId";
}

1;
