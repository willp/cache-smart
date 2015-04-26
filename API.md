# Introduction #

This describes the platform-neutral API for interacting with the CacheSmart library, with footnotes to describe specific differences between the various language implementations.

# Details #

## Constructor ##

Required arguments:

  * name (String) => Must identify uniquely this cache from all other caches in this application. No default.

Optional arguments:

  * 
  * max\_size\_entries (integer) => Not Yet Implemented.
  * max\_size\_bytes (integer) => Not Yet Implemented.
  * time\_func (code ref) => reference to function that will return the current time. Only useful for unit tests of the code itself, or unique edge-cases.  Default is the platform time() function.


## get() ##

Required arguments:

  * key (string) =>

Optional arguments:

  * context (string) =>

Add your content here.  Format your content with:
  * Text in **bold** or _italic_
  * Headings, paragraphs, and lists
  * Automatic links to other wiki pages