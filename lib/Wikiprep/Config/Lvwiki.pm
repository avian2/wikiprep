# vim:sw=2:tabstop=2:expandtab

use encoding 'utf-8';

# Latvian Wikipedia
# --------------------------------------------------------------------------------------------

# Names of months as used by MediaWiki for date links
# FIXME
%numberToMonth = (
                      1 => 'Januar', 
                      2 => 'Februar', 
                      3 => 'Marec', 
                      4 => 'April',
                      5 => 'Maj', 
                      6 => 'Junij', 
                      7 => 'Julij', 
                      8 => 'Avgust', 
                      9 => 'September', 
                      10 => 'Oktober', 
                      11 => 'November', 
                      12 => 'December'
                  );

$namespaceAliases = ();

# Following three are pre-compiled regular expressions used for recognizing links to 
# related articles.

# We require that stanalone designators occur at the beginning of the line
# (after at most a few characters, such as a whitespace or a colon),
# and not just anywhere in the line. Otherwise, we would collect as related
# those links that just happen to occur in the same line with an unrelated
# string that represents a standalone designator.

# FIXME
$relatedWording_Standalone = qr/Glavni(?:\s+)član(ek|ki)|
                                Dodatne(?:\s+)informacije|
                                Povezani(?:\s+)član(ek|ki)|
                                Povezan(a|e)(?:\s+)tem(a|e)|
                                Glej(?:\s+)glavn(i|e)(?:\s+)član(ek|ke)|
                                Glej(?:\s+)član(ek|ke)|
                                Glej(?:\s+)tudi|
                                Za(?:\s+)(?:več|dodatn[io]|nadaljn[io])/ix;

# Can appear anywhere in text, but must be enclosed in parentheses.

# FIXME
$relatedWording_Inline = qr/Glej[\s:]|
                            Glej(?:\s+)tudi|
                            Za(?:\s+)(?:več|dodatn[io]|nadaljn[io])/ix;

# Article sections containing links to related articles.

# FIXME
$relatedWording_Section = qr/Dodatne(?:\s+)informacije|
                             Glej(?:\s+)tudi|
                             Povezani?(?:\s+)član(ek|ki)|
                             Povezan[ea](?:\s+)tem[ea]/ix;

# We only process pages in these namespaces + the main namespace (which has an empty name)

%okNamespacesForPrescanning = (
                                'Kategorija' => 1, 
                                'Palīdzība' => 1, 
                                'Attēls' => 1 
                              );

# Pages in these namespaces end up in the final hgw.xml file.

%okNamespacesForTransforming = (
                                'Kategorija' => 1, 
                                'Attēls' => 1
                              );

# Pages in these namespaces that don't exist in the XML dump but have a link to it, 
# get assigned a local ID. Broken links to other pages get ignored.

# 1 means that links for that namespace are extracted and their anchors 
# included in the text.

# 2 means that links are extracted, but their anchors are ignored.

%okNamespacesForInterwikiLinks = (
                                'Attēls' => 1,

                                'En'  => 2,
                              );

# Namespace for categories.

$categoryNamespace = 'Kategorija';

# Namespace for templates.

$templateNamespace = 'Palīdzība';

# namespace for images.

$imageNamespace = 'Attēls';

# Regular expression that matches names of templates that mark disambiguation articles.

# FIXME
$disambigTemplates = qr/razločitev|
                        razločitveni|
                        disambig|
                        dab/ix;

# Regular expression that matches titles of disambiguation articles.

# FIXME
$disambigTitle = qr/\(razdvojba\)/ix;

# Regular expression that matches article text if the article is a redirect.

$isRedirect = qr/^#REDIRECT/i;

# Regular expression that extracts the title the redirect points to. Note that this 
# is only used if $isRedirect matches the text of the redirect page.

$parseRedirect = qr/^\#REDIRECT
                    (?:S|ED|ION)?
                    \s*                 # optional whitespace
                    (?: :|\sTO|=)?      # optional colon, "TO" or "="
                                        #   (in case of "TO", we expect a whitespace before it,
                                        #    so that it's not glued to the preceding word)
                    \s*                 # optional whitespace
                    \[\[([^\]]*)\]\]    # the link itself
                   /ix;

1;
