# vim:sw=2:tabstop=2:expandtab

use encoding 'utf-8';

# Names of months as used by MediaWiki for date links

%numberToMonth = (
    1 => 'Январь', 
    2 => 'Февраль', 
    3 => 'Март', 
    4 => 'Апрель',
    5 => 'Май', 
    6 => 'Июнь', 
    7 => 'Июль', 
    8 => 'Август', 
    9 => 'Сентябрь', 
    10 => 'Октябрь', 
    11 => 'Ноябрь', 
    12 => 'Декабрь'
);

# Aliases for namespaces. Link [[Image:X]] is identical to [[File:X]]. XML dump file
# contains only pages in the File: namespace.

%namespaceAliases = (
                      'Image' => 'File'
                 );

# Following three are pre-compiled regular expressions used for recognizing links to 
# related articles.

# We require that stanalone designators occur at the beginning of the line
# (after at most a few characters, such as a whitespace or a colon),
# and not just anywhere in the line. Otherwise, we would collect as related
# those links that just happen to occur in the same line with an unrelated
# string that represents a standalone designator.

$relatedWording_Standalone =
    qr/Основная(?:\s+)статья(?:s?)|
       Основные(?:\s+)статьи(?:s?)|
       Further(?:\s+)information|
       Related(?:\s+)article(?:s?)|
       Related(?:\s+)topic(?:s?)|
       See(?:\s+)main(?:\s+)article(?:s?)|
       See(?:\s+)article(?:s?)|
       См\.(?:\s+)также|
       См\.(?:\s+)также(?:\s+)статью|
       For(?:\s+)(?:more|further)/ix;
## For(?:\s+)more(?:\s+)(?:background|details)(?:\s+)on(?:\s+)this(?:\s+)topic,(?:\s+)see
                  
%overrideTemplates = (
                        'Template:Int:Lang' => 'ru'
                     );


# Can appear anywhere in text, but must be enclosed in parentheses.

$relatedWording_Inline =
    qr/См\.[\s:]|
       См\.(?:\s+)также|
       For(?:\s+)(?:more|further)/ix;

# Article sections containing links to related articles.

$relatedWording_Section =
    qr/Further(?:\s+)information|
       See(?:\s+)also|
       Related(?:\s+)article(?:s?)|
       Related(?:\s+)topic(?:s?)/ix;

# We only process pages in these namespaces + the main namespace (which has an empty name)

%okNamespacesForPrescanning = (
    'Шаблон' => 1, 
    'Категория' => 1, 
    'Изображение' => 1
);

# Pages in these namespaces end up in the final hgw.xml file.

%okNamespacesForTransforming = (
    'Категория' => 1, 
    'Изображение' => 1
);

# Interwiki links are links to another wiki (e.g. from Wikipedia article to an image on 
# Wikimedia Commons or to a MemoryAlpha article).
#
# These links appear as internal links in the browser. Syntax is similar to MediaWiki namespaces: 
# for example [[MemoryAlpha:Test]] or [[MemoryAlpha:Category:Test]].

# See http://meta.wikimedia.org/wiki/Interwiki_map for a comprehensive list of possible destinations. 

# Only a few largest wikis are enabled here for performance reasons

# If a namespace here overlaps with local namespace (e.g. File), the local namespace has
# higher priority. If a local page does not exist in that namespace, the link is considered to be
# interwiki.

%okNamespacesForInterwikiLinks = (
                      File           => 1,

        		          Wookieepedia   => 1,
                  		Memoryalpha    => 1,
                  		Wowwiki        => 1,
                  		Marveldatabase => 1,
                  		Dcdatabase     => 1,
                    );


# Pages in these namespaces that don't exist in the XML dump but have a link to it, 
# get assigned a local ID. Broken links to other pages get ignored.

$okNamespacesForLocalPages = {
    'Изображение' => 1
};

# Namespace for categories.

$categoryNamespace = 'Категория';

# Namespace for templates.

$templateNamespace ='Шаблон';

# namespace for images.

$imageNamespace = 'Изображение';

# Regular expression that matches names of templates that mark disambiguation articles.

$disambigTemplates =
    qr/неоднозначность|
       disambig|
       disambig-cleanup|
       dab|
       hndis|
       surname|
       geodis|
       schooldis|
       hospitaldis|
       mathdab|
       numberdis/ix;

# Regular expression that matches titles of disambiguation articles.

$disambigTitle = qr/\(значения\)/ix;
                      
# Regular expression that matches article text if the article is a redirect.

$isRedirect = qr/^#REDIRECT/i;

# Regular expression that extracts the title the redirect points to. Note that this 
# is only used if $isRedirect matches the text of the redirect page.

$parseRedirect = qr/^\#REDIRECT         # Redirect must start with "#REDIRECT"
                    (?:S|ED|ION)?       # The word may be in any of these forms,
                                        #   i.e., REDIRECT|REDIRECTS|REDIRECTED|REDIRECTION
                    \s*                 # optional whitespace
                    (?: :|\sTO|=)?      # optional colon, "TO" or "="
                                        #   (in case of "TO", we expect a whitespace before it,
                                        #    so that it's not glued to the preceding word)
                    \s*                 # optional whitespace
                    \[\[([^\]]*)\]\]    # the link itself
                   /ix;

1;
