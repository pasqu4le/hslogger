{- arch-tag: I/O utilities main file
Copyright (C) 2004 John Goerzen <jgoerzen@complete.org>

This program is free software; you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation; either version 2 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program; if not, write to the Free Software
Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA
-}

{- | This module provides various helpful utilities for dealing with I\/O.

Written by John Goerzen, jgoerzen\@complete.org
-}

module MissingH.IOutil(-- * Line Processing Utilities
                       hPutStrLns, hGetLines,
                       -- * Lazy Interaction
                       hInteract, lineInteract, hLineInteract,
                       -- * Binary Files
                       hPutBufStr, hGetBufStr, hFullGetBufStr
                        ) where

import Foreign.Ptr
import Foreign.ForeignPtr
import Foreign.C.String
import System.IO.Unsafe
import System.IO

{- | Given a list of strings, output a line containing each item, adding
newlines as appropriate.  The list is not expected to have newlines already.
-}

hPutStrLns :: Handle -> [String] -> IO ()
hPutStrLns _ [] = return ()
hPutStrLns h (x:xs) = do
                      hPutStrLn h x
                      hPutStrLns h xs

{- | Given a handle, returns a list of all the lines in that handle.
Thanks to lazy evaluation, this list does not have to be read all at once.

Combined with 'hPutStrLns', this can make a powerful way to develop
filters.  See the 'lineInteract' function for more on that concept.

Example:

> main = do
>        l <- hGetLines stdin
>        hPutStrLns stdout $ filter (startswith "1") l

-}

hGetLines :: Handle -> IO [String]

hGetLines h = unsafeInterleaveIO (do
                                  ieof <- hIsEOF h
                                  if (ieof) 
                                     then return []
                                     else do
                                          line <- hGetLine h
                                          remainder <- hGetLines h
                                          return (line : remainder)
                                 )


{- | This is similar to the built-in 'System.IO.interact', but works
on any handle, not just stdin and stdout.

In other words:

> interact = hInteract stdin stdout
-}
hInteract :: Handle -> Handle -> (String -> String) -> IO ()
hInteract finput foutput func = do
                                content <- hGetContents finput
                                hPutStr stdout (func content)

{- | Line-based interaction.  This is similar to wrapping your
interact functions with 'lines' and 'unlines'.  This equality holds:

> lineInteract = 'hLineInteract' stdin stdout

Here's an example:

> main = lineInteract (filter (startswith "1"))
-}
lineInteract :: ([String] -> [String]) -> IO ()
lineInteract = hLineInteract stdin stdout

{- | Line-based interaction over arbitrary handles.  This is similar
to wrapping hInteract with 'lines' and 'unlines'.

One could view this function like this:

> hLineInteract finput foutput func = 
>     let newf = unlines . func . lines in
>         hInteract finput foutput newf

Though the actual implementation is this for efficiency:

> hLineInteract finput foutput func =
>     do
>     lines <- hGetLines finput
>     hPutStrLns foutput (func lines)
-}

hLineInteract :: Handle -> Handle -> ([String] -> [String]) -> IO ()
hLineInteract finput foutput func =
    do
    lines <- hGetLines finput
    hPutStrLns foutput (func lines)

-- . **************************************************
-- . Binary Files
-- . **************************************************


{- | As a wrapper around the standard function 'System.IO.hPutBuf',
this function takes a standard Haskell 'String' instead of the far less
convenient 'Ptr a'.  The entire contents of the string will be written
as a binary buffer using 'hPutBuf'.  The length of the output will be
the length of the string. -}
hPutBufStr :: Handle -> String -> IO ()
hPutBufStr f s = withCString s (\cs -> hPutBuf f cs (length s))

{- | As a wrapper around the standard function 'System.IO.hGetBuf',
this function returns a standard Haskell string instead of modifying
a 'Ptr a' buffer.  The length is the maximum length to read and the
semantice are the same as with 'hGetBuf'; namely, the empty string
is returned with EOF is reached, and any given read may read fewer
bytes than the given length. -}
hGetBufStr :: Handle -> Int -> IO String
hGetBufStr f count = do
   fbuf <- mallocForeignPtrArray (count + 1)
   withForeignPtr fbuf (\buf -> do
                        bytesread <- hGetBuf f buf count
                        haskstring <- peekCStringLen (buf, bytesread)
                        return haskstring)

{- | Like 'hGetBufStr', but guarantees that it will only return fewer than
the requested number of bytes when EOF is encountered. -}
hFullGetBufStr :: Handle -> Int -> IO String
hFullGetBufStr f 0 = return ""
hFullGetBufStr f count = do
                         thisstr <- hGetBufStr f count
                         if thisstr == "" -- EOF
                            then return ""
                            else do
                                 remainder <- hFullGetBufStr f (count - (length thisstr))
                                 return (thisstr ++ remainder)
