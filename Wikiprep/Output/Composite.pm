# vim:sw=2:tabstop=2:expandtab

package Wikiprep::Output::Composite;

use warnings;
use strict;

use Wikiprep::utils qw( encodeXmlChars getLinkIds removeDuplicatesAndSelf );
use Wikiprep::templates;
use Wikiprep::interwiki;

use XML::Writer;
use IO::File;

sub new 
{
	my $class = shift;

	my $basepath = shift;
  my $inputFile = shift;
  my %params = @_;

  my $unsafe = not $params{DEBUG};

  my $gumFile;
  if( $params{COMPRESS} ) {
    $gumFile = IO::File->new("| gzip >$basepath.gum.xml.gz");
  } else {
    $gumFile = IO::File->new("> $basepath.gum.xml");
  }
  my $gumWriter = XML::Writer->new(OUTPUT => $gumFile, DATA_MODE => 1, ENCODING => "utf-8", 
                                                                       UNSAFE => $unsafe );
  $gumWriter->xmlDecl();
  $gumWriter->startTag("gum");

  my $localFile = IO::File->new("> $basepath.local.xml");
  my $localWriter = XML::Writer->new(OUTPUT => $localFile, DATA_MODE => 1, ENCODING => "utf-8",
                                                                           UNSAFE => $unsafe );
  $localWriter->xmlDecl();
  $localWriter->startTag("pages");

  my $redirFile = IO::File->new("> $basepath.redir.xml");
  my $redirWriter = XML::Writer->new(OUTPUT => $redirFile, DATA_MODE => 1, ENCODING => "utf-8",
                                                                           UNSAFE => $unsafe );
  $redirWriter->xmlDecl();
  $redirWriter->startTag("redirects");

  my $tmplFile = IO::File->new("> $basepath.tmpl.xml");
  my $tmplWriter = XML::Writer->new(OUTPUT => $tmplFile, DATA_MODE => 1, ENCODING => "utf-8",
                                                                         UNSAFE => $unsafe );
  $tmplWriter->xmlDecl();
  $tmplWriter->startTag("templates");

  my $self = { 
                gumFile    => $gumFile,
                gumWriter  => $gumWriter,

                localFile    => $localFile,
                localWriter  => $localWriter,

                redirFile    => $redirFile,
                redirWriter  => $redirWriter,

                tmplFile    => $tmplFile,
                tmplWriter  => $tmplWriter,
             };

  my $localIDFile = "$basepath.min_local_id";
  open( $self->{localidFile}, "> $localIDFile") or 
    die "Cannot open $localIDFile: $!";

  my $disambigFile = "$basepath.disambig";
  open( $self->{disambigFile}, "> $disambigFile") or 
    die "Cannot open $disambigFile: $!";
  binmode($self->{disambigFile}, ':utf8');

  print {$self->{disambigFile}} "# Line format: <Disambig page id>  <Target page id (or \"undef\")> <Target anchor> ...\n\n\n";

  my $anchorFile = "$basepath.anchor_text";
  if( $params{COMPRESS} ) {
    open( $self->{anchorFile}, "| gzip >$anchorFile.gz") or 
      die "Cannot open to gzip: $anchorFile.gz: $!";
  } else {
    open( $self->{anchorFile}, "> $anchorFile") or 
      die "Cannot open $anchorFile.gz: $!";
  }
  binmode($self->{anchorFile}, ':utf8');

  print {$self->{anchorFile}} "# Line format: <Target page id>  <Source page id>  <Anchor location within text>  <Anchor text (up to the end of the line)>\n\n\n";

	bless $self, $class;

	return $self;
}

sub finish
{
  my $self = shift;

  $self->{gumWriter}->endTag();
  $self->{gumWriter}->end();
  $self->{gumFile}->close();

  $self->{localWriter}->endTag();
  $self->{localWriter}->end();
  $self->{localFile}->close();

  $self->{redirWriter}->endTag();
  $self->{redirWriter}->end();
  $self->{redirFile}->close();

  $self->{tmplWriter}->endTag();
  $self->{tmplWriter}->end();
  $self->{tmplFile}->close();

  close( $self->{localidFile} );

  close( $self->{disambigFile} );
  close( $self->{anchorFile} );
}

sub lastLocalID
{
  my $self = shift;
  my ($localIDCounter) = @_;

  print {$self->{localidFile}} "$localIDCounter\n";
}

sub newLocalID
{
  my $self = shift;
  my ($id, $title) = @_;

  my $writer = $self->{localWriter};

  $writer->startTag("page");
  $writer->dataElement("id", $id);
  $writer->dataElement("title", $title);
  $writer->endTag("page");
}

# Save information about redirects into an XML-formatted file.
sub writeRedirects 
{
  my $self = shift;
  my ($refToRedir, $refToTitle2Id, $refToTemplates) = @_;

  my $writer = $self->{redirWriter};

  while(my ($fromTitle, $toTitle) = each(%$refToRedir)) {

    my $fromId = $refToTitle2Id->{$fromTitle} || "unknown";
    my $toId = $refToTitle2Id->{$toTitle} || "unknown";

    if( exists( $refToTemplates->{$fromId} ) ) {
      next;
    } elsif( exists( $refToTemplates->{$toId} ) ) {
      $self->{tmplWriter}->startTag("template");
      $self->{tmplWriter}->dataElement("name", $fromTitle);
      $self->{tmplWriter}->dataElement("id", $toId);
      $self->{tmplWriter}->endTag("template");
    } else {
      $writer->startTag("redirect");
      $writer->startTag("from");
      $writer->dataElement("id", $fromId);
      $writer->dataElement("name", $fromTitle);
      $writer->endTag("from");
      $writer->startTag("to");
      $writer->dataElement("id", $toId);
      $writer->dataElement("name", $toTitle);
      $writer->endTag("to");
      $writer->endTag("redirect");
    }
  }
}

sub newTemplate 
{
  my $self = shift;
  my ($id, $title) = @_;

  my $writer = $self->{tmplWriter};

  $writer->startTag("template");
  $writer->dataElement("name", $title);
  $writer->dataElement("id", $id);
  $writer->endTag("template");
}

sub newPage 
{
  my $self = shift;
  my ($page) = @_;

  my @internalLinks;
  &getLinkIds(\@internalLinks, $page->{internalLinks});
  &removeDuplicatesAndSelf(\@internalLinks, $page->{id});

  my $writer = $self->{gumWriter};

  $writer->startTag("page", id          => $page->{id},
                            orglength   => $page->{orgLength},
                            newlength   => $page->{newLength},
                            stub        => $page->{isStub},
                            disambig    => $page->{isDisambig},
                            category    => $page->{isCategory});

  $writer->dataElement("title", $page->{title});

  $writer->dataElement("categories", join(" ", @{$page->{categories}}));

  $writer->dataElement("links", join(" ", @internalLinks));

  $writer->dataElement("related", join(" ", @{$page->{relatedArticles}}));

  $writer->startTag("external");
  for my $link (@{$page->{externalLinks}}) {
      $writer->startTag("link");
      if( $link->{anchor} ) {
        $writer->dataElement("anchor", $link->{anchor});
      }
      $writer->dataElement("url", $link->{url});
      $writer->endTag("link");
  }
  $writer->endTag("external");

  $writer->startTag("interwiki");
  for my $link (@{$page->{interwikiLinks}}) {
      $writer->startTag("link");
      $writer->dataElement("wiki", $link->{targetWiki});
      $writer->dataElement("title", $link->{targetTitle});
      $writer->endTag("link");
  }
  $writer->endTag("interwiki");

  $writer->startTag("templates");
  while(my ($templateId, $log) = each(%{$page->{templates}})) {
    $writer->startTag("template", id => $templateId);
    for my $refToParameterHash (@$log) {
      $writer->startTag("include");
      while( my ($parameter, $value) = each(%$refToParameterHash) ) {
        if($parameter !~ /^=/) {
          $writer->dataElement("parameter", $value, name => $parameter)
        }
      }
      $writer->endTag("include");
    }
    $writer->endTag("template");
  }
  $writer->endTag("templates");

  print {$self->{gumFile}} "<text>", $page->{text}, "</text>";

  $writer->endTag("page");

  $self->_logDisambig($page);
  $self->_logAnchorText($page);
}

sub _logDisambig 
{
  my $self = shift;
	my ($page) = @_;

  return unless $page->{isDisambig};

  my $file = $self->{disambigFile};

  for my $disambigLinks (@{$page->{disambigLinks}}) {

	  print $file $page->{id};

    for my $anchor (@$disambigLinks) {
      if( defined( $anchor->{'targetId'} ) ) {
        print $file "\t$anchor->{'targetId'}";
      } else {
        print $file "\tundef";
      }
      print $file "\t$anchor->{'anchorText'}"
    }

  	print $file "\n";
  }
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

      print {$self->{anchorFile}} "$targetId\t$page->{id}\t$linkLocation\t$anchorText\n";
    }
  }
}

1;
