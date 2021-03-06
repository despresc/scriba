{
module Scriba.Markup.ScribaML.Lexer
  ( lexToken
  , lexTokens
  , alexScan )
where


import Control.Monad.State (MonadState(..))
import Scriba.Markup.ScribaML.LexerActions
import Scriba.Markup.ScribaML.ParserDefs
import Scriba.Markup.ScribaML.Token
import qualified Data.Text as T
}

$startLineSpecialChar = [\\ \[ \]  \{ \} = \  \n \, \# &]
$midLineSpecialChar = $startLineSpecialChar # [\#]
$whitespace = [\  \n]
$startLinePlainText = $printable # $startLineSpecialChar
$midLinePlainText = $printable # $midLineSpecialChar
$identish = $printable # [ \[ \] \{ \} \  \n \\]
$verbatimPlain = [^ \  \n `]
$backslash = [\\]
$inlineStarter = $identish # [` \% \# &]

@blanks = (\n | \ )*
@indent = \n @blanks

tokens :-

<0> {
  -- we are a little strict here. if there is no white space we recover in
  -- lexToken.
  (\n | \ )+ { textTok Blanks `thenCode` plainTextBeginLine}
}

-- the only differences between begin line and mid line is that begin line
-- doesn't need to recognize white space tokens, and mid line should not
-- recognize level tags

<plainTextBeginLine> {
  $startLinePlainText+ { textTok PlainText `thenCode` plainTextMidLine }

  "{" { doStartBraceGroup `thenCode` plainTextMidLine }
  "}" { doEndBraceGroup `thenCode` plainTextMidLine }
  "[" { doStartAttrSet `thenCode` plainTextMidLine }
  "]" { doEndAttrSet `thenCode` plainTextMidLine }
  "=" { plainTok Equals `thenCode` plainTextMidLine }
  "," { plainTok Comma `thenCode` plainTextMidLine }

  "\\" { plainTok (Escape EscBackslash) `thenCode` plainTextMidLine }
  "\{" { plainTok (Escape EscLbrace) `thenCode` plainTextMidLine }
  "\}" { plainTok (Escape EscRbrace) `thenCode` plainTextMidLine }
  "\[" { plainTok (Escape EscLbracket) `thenCode` plainTextMidLine }
  "\]" { plainTok (Escape EscRbracket) `thenCode` plainTextMidLine }
  "\&" { plainTok (Escape EscAnd) `thenCode` plainTextMidLine }
  "\#" { plainTok (Escape EscNum) `thenCode` plainTextMidLine }

  "\`" { doStartInlineVerbatim `thenCode` verbatimPlain }
  "\%" .* { doLineComment `thenCode` plainTextMidLine }

  "&" $identish+ { doLayoutTag `thenCode` plainTextMidLine }
  "\" $inlineStarter $identish* { doInlineTag `thenCode` plainTextMidLine }
  "#"+ $identish+ { doLevelTag `thenCode` plainTextMidLine }
}

<plainTextMidLine> {
  $midLinePlainText+ { textTok PlainText }

  \ + { \toklen spn _ -> pure $ Located spn $ LineSpace toklen }
  @indent { doBlanks `thenCode` plainTextBeginLine}

  "{" { doStartBraceGroup }
  "}" { doEndBraceGroup }
  "[" { doStartAttrSet }
  "]" { doEndAttrSet }
  "=" { plainTok Equals }
  "," { plainTok Comma }

  "\\" { plainTok $ Escape EscBackslash }
  "\{" { plainTok $ Escape EscLbrace }
  "\}" { plainTok $ Escape EscRbrace }
  "\[" { plainTok $ Escape EscLbracket }
  "\]" { plainTok $ Escape EscRbracket }
  "\&" { plainTok $ Escape EscAnd }
  "\#" { plainTok $ Escape EscNum }

  "\`" { doStartInlineVerbatim `thenCode` verbatimPlain }
  "\%" .* { doLineComment }

  "&" $identish+ { doLayoutTag }
  "\" $inlineStarter $identish* { doInlineTag }
}

<verbatimPlain> {
  $verbatimPlain+ { textTok InlineVerbatimText }
  \ + { \toklen spn _ -> pure $ Located spn $ LineSpace toklen }
  @indent { doVerbatimBlanks }
  "``" { plainTok $ VerbatimBacktick }
  "`/" { doEndInlineVerbatim `thenCode` plainTextMidLine }
}

{

-- | Parse a single token from the input stream
lexToken :: Parser (Located Token)
lexToken = do
  parsestate@(ParseState sc inp toks _ _ _ _) <- get
  case toks of
    (t:toks') -> put (parsestate { parseStatePendingTokens = toks' }) *> pure t
    _ -> case alexScan inp sc of
            AlexEOF -> doEOF
            AlexError ai
              | sc == 0 -> do
                  put $ parsestate {parseStateStartCode = plainTextBeginLine}
                  lexToken
              | otherwise -> do
                  let nm = alexInputSrcName ai
                  let pos = alexInputSrcPos ai
                  throwLexError (SrcSpan nm pos pos) NoToken
            AlexSkip inp' _ -> setInput inp' *> lexToken
            AlexToken inp' toklen act -> do
              let initPos = alexInputSrcPos inp
              let finalPos = alexInputSrcPos inp'
              let name = alexInputSrcName inp
              let posSpan = SrcSpan name initPos finalPos
              setInput inp' *> act toklen posSpan (T.take toklen $ alexInputText inp)

-- | Tokenize the entire input stream
lexTokens :: Parser [Located Token]
lexTokens = go id
  where
    go acc = do
      tok <- lexToken
      case locatedVal tok of
        TokenEOF -> pure $ acc []
        _ -> go (acc . (tok :))
}
