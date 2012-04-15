{-# LANGUAGE FlexibleContexts, FlexibleInstances, MultiParamTypeClasses, UndecidableInstances, QuasiQuotes, TypeSynonymInstances #-}
{-# OPTIONS_GHC -fno-warn-orphans #-}
-- | This module provides support for embedding javascript generated by jmacro into HSX.
--
-- It provides the following instances:
--
-- > instance (XMLGenerator m, IntegerSupply m) => EmbedAsChild m JStat
-- > instance (IntegerSupply m, IsName n, EmbedAsAttr m (Attr Name String)) => EmbedAsAttr m (Attr n JStat)
-- > instance ToJExpr (Ident XML)
-- 
-- In order to ensure that each embedded 'JStat' block has unique
-- variable names, the monad must supply a source of unique
-- names. This is done by adding an instance of 'IntegerSupply' for
-- the monad being used with 'XMLGenerator'.
--
-- For example, an 'IntegerSupply' for 'ServerPartT':
--
-- > instance IntegerSupply (ServerPartT (StateT Integer IO)) where
-- >     nextInteger = nextInteger'
--
-- This variation avoids the use of an extra monad transformer:
--
-- > instance IntegerSupply (ServerPartT IO) where
-- >     nextInteger = fmap (fromIntegral . (`mod` 1024) . hashUnique) (liftIO newUnique)
--
-- The @ToJExpr@ instance allows you to run HSP in the Identity monad via
-- 'Ident', to generate DOM nodes with JMacro antiquotation:
--
-- > html :: Ident XML
-- > html = <p>This paragraph inserted using <em>JavaScript</em>!</p>
-- > js = [jmacro| document.getElementById("messages").appendChild(`(html)`); |]
module HSX.JMacro where

import qualified HSP.Identity              as HSP
import qualified Happstack.Server.HSP.HTML as HTML

import Control.Monad.Trans             (lift)
import Control.Monad.State             (MonadState(get,put))
import HSX.XMLGenerator                (XMLGenerator(..), XMLGen(..), EmbedAsChild(..), EmbedAsAttr(..), IsName(..), Attr(..), Name)
import Language.Javascript.JMacro      (JStat(..), JExpr(..), JVal(..), Ident(..), ToJExpr(..), jmacroE, jLam, jVarTy, jsToDoc, jsSaturate, renderPrefixJs)
import Text.PrettyPrint.HughesPJ       (Style(..), Mode(..), renderStyle, style)

class IntegerSupply m where 
    nextInteger :: m Integer

-- | This help function allows you to easily create an 'IntegerSupply'
-- instance for monads that have a 'MonadState' 'Integer' instance.
--
-- For example:
--
-- > instance IntegerSupply (ServerPartT (StateT Integer IO)) where
-- >     nextInteger = nextInteger'
nextInteger' :: (MonadState Integer m) => m Integer
nextInteger' =
    do i <- get
       put (succ i)
       return i

instance (XMLGenerator m, IntegerSupply m) => EmbedAsChild m JStat where
  asChild jstat = 
      do i <- lift nextInteger
         asChild $ genElement (Nothing, "script")
                    [asAttr ("type" := "text/javascript")]
                    [asChild (renderStyle lineStyle $ renderPrefixJs (show i) jstat)]
      where
        lineStyle = style { mode= OneLineMode }

instance (IntegerSupply m, IsName n, EmbedAsAttr m (Attr Name String)) => EmbedAsAttr m (Attr n JStat) where
  asAttr (n := jstat) = 
      do i <- lift nextInteger
         asAttr $ (toName n := (renderStyle lineStyle $ renderPrefixJs (show i) jstat))
      where
        lineStyle = style { mode= OneLineMode }

instance ToJExpr (HSP.Ident HTML.XML) where
  toJExpr xml =
    [jmacroE| (function { var node = document.createElement('div')
                        ; node.innerHTML = `(HTML.renderAsHTML . HSP.evalIdentity $ xml)`
                        ; return node.childNodes[0]
                        })() |]
