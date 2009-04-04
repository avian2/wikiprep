use Regexp::Common;

# Template call parsing

sub _splitTemplateInvocationFast($) {

  my ($refToTemplateInvocation) = @_;

  return split(/\|/, $$refToTemplateInvocation);
}

sub _splitTemplateInvocationSlow($) {

  my ($refToTemplateInvocation) = @_;

  # This is a simple parser that splits the invocation string on those "|" symbols that are not
  # nested within "[" or "{" braces.
  
  # We first split the string into tokens - symbols we care about and other text.

  my $brace = 0;
  my $square = 0;
  my $accumulator = "";
  my @parameters = ();

  # Iterate through tokens and gather them into the accumulator

  my $token;
  for $token ( split(/([\{\}\[\]\|])/, $$refToTemplateInvocation ) ) {
    if( $token eq '|' and $brace == 0 and $square == 0 ) {

      # Unnested "|" means we store the contents of the accumulator into a new parameter

      push(@parameters, $accumulator);
      $accumulator = "";
    } else {
      if( $token eq '{' ) {
        $brace ++;
      } elsif( $token eq '}' ) {
        $brace -- if $brace > 0;
      } elsif( $token eq '[' ) {
        $square ++;
      } elsif( $token eq ']' ) {
        $square -- if $square > 0;
      }
      $accumulator .= $token;
    }
  }
  push(@parameters, $accumulator);

  return @parameters;
}

sub splitTemplateInvocation($) {
  my $templateInvocation = shift;

  if( $templateInvocation =~ /[\{\[]/ ) {
    return &_splitTemplateInvocationSlow(\$templateInvocation);
  } else {
    return &_splitTemplateInvocationFast(\$templateInvocation);
  }
}

# Regular expression that matches a template include directive. It is replaced with fully
# expanded template text in includeTemplates() below.

# Matches two opening braces with any balanced combination of braces within. Note that this also
# matches for example {{{3}}} (which can happen if we get an unexpanded template parameter in the
# output). This case is handled as an unknown template, which is then replaced by an empty string.

# (some pages have template parameters in them although they are not templates)

my $templateRegex = qr/(\{$Regexp::Common::RE{balanced}{-parens => "{}"}\})/s;

sub splitOnTemplates($) {
  my $text = shift;

  my @retval;
  my $invocation = 0;

  for my $i ( split(/$templateRegex/s, $text) ) {
    if( $invocation ) {
      $i =~ s/^\{\{//;
      $i =~ s/\}\}$//;
      $invocation = 0;
    } else {
      $invocation = 1;
    }
    push(@retval, $i);
  }

  return @retval;
}

1;
