{-# LANGUAGE DeriveFunctor, DeriveFoldable, DeriveTraversable #-}
{-# LANGUAGE OverloadedStrings, RecordWildCards, ViewPatterns #-}
module HipSpec.Lang.PrettyWhy3 where

import Data.Foldable (Foldable)
import Data.Traversable (Traversable)
import Data.Generics.Geniplate (universeBi)

import Text.PrettyPrint

import HipSpec.Lang.Simple (injectExpr)
import HipSpec.Lang.Rich
import HipSpec.Lang.PrettyUtils hiding (pp_symb,pp_var)
import HipSpec.Lang.Type
import HipSpec.Property

-- Why3 Pretty priting Kit
-- The user has to make sure that only data constructors have an initial
-- uppercase letter.
-- Aphostrophes are added automatically to type variables.
data Eq a => PK a = PK { pp_symb :: a -> Doc }

data Why3Theory a = Why3Theory [[Datatype a]] [[Function a]] [Property' a]
  deriving (Functor,Foldable,Traversable)

end :: Doc -> Doc
end d = d $$ "end"

ppProg :: Eq a => PK a -> Why3Theory a -> Doc
ppProg pk (Why3Theory dss fss ps) =
  end $
    "module" <+> "A" $\
    vcat (
        "use HighOrd" :
        map (ppData pk) (concat dss) ++
        map (ppFuns pk) fss ++
        map (ppProp pk) ps)

ppProp :: Eq a => PK a -> Property' a -> Doc
ppProp pk Property{..} =
  ("goal" <+> text prop_name <+> ":")
  $\ ppQuant pk prop_vars
      (fsep (punctuate " ->" (map (ppLit pk) (prop_assums ++ [prop_goal]))))

ppLit :: Eq a => PK a -> Literal' a -> Doc
ppLit pk (a :=: b) = ppExpr pk (injectExpr a) <+> "=" $\ ppExpr pk (injectExpr b)

ppQuant :: Eq a => PK a -> [(a,Type a)] -> Doc -> Doc
ppQuant _pk []  d = d
ppQuant pk  xts d =
  ("forall" $\ fsep (punctuate "," (map (uncurry (ppBinder pk)) xts)) <+> ".") $\ d

ppData :: Eq a => PK a -> Datatype a -> Doc
ppData pk (Datatype tc tvs cons) =
  "type" $\ (pp_symb tc $\ sep (map (ppTyVar pk) tvs) $\
    separating fsep ("=":repeat "|") (map (ppCon pk) cons))
  where PK{..} = pk

ppCon :: Eq a => PK a -> Constructor a -> Doc
ppCon pk (Constructor c as) =
    pp_symb c <+> fsep (map (ppType pk 1) as)
  where PK{..} = pk

separating :: ([Doc] -> Doc) -> [Doc] -> [Doc] -> Doc
separating comb seps docs = comb (go seps docs)
  where
    go (s:ss) (d:ds) = s <+> d : go ss ds
    go _      []     = []
    go []     _      = error "separating: ran out of separators!"

{-
ppQuant :: Eq a => PK a -> Doc -> [(a,Doc)] -> Doc -> Doc
ppQuant pk q xs d = case xs of
    [] -> d
    _  -> (q <> bsv [ pp_var x `typeSig` t | (x,t) <- xs] <> ":") $\ d
  where
    bsv [] = empty
    bsv xs = brackets (fsep (punctuate "," xs))
    PK{..} = pk
    -}

ppBinder :: Eq a => PK a -> a -> Type a -> Doc
ppBinder pk x t = pp_symb x <+> ":" $\ ppType pk 0 t
  where PK{..} = pk

ppFuns :: Eq a => PK a -> [Function a] -> Doc
ppFuns pk (fn:fns) = vcat (ppFun pk "function" fn:[ppFun pk "with" f|f<-fns])

ppFun :: Eq a => PK a -> Doc -> Function a -> Doc
ppFun pk name (Function f (Forall _tvs ft) (collectBinders -> (xts,e))) =
    ((name $\ pp_symb f) $\
        fsep [ parens (ppBinder pk x xt) | (x,xt) <- xts ]
       $\ (":" <+> ppType pk 0 t <+> "="))
     $\ (ppExpr pk e)
  where
    PK{..} = pk
    Just t = peelArrows ft (length xts)

ppExpr :: Eq a => PK a -> Expr a -> Doc
ppExpr pk e00 =
  case e00 of
    Gbl x (Forall tvs t) ts
      | or [ const True (x `asTypeOf` head tvs) | t <- ts, TyVar x <- universeBi t ]
      -> parens (pp_symb x <+> ":" $\ ppType pk 0 (substManyTys (zip tvs ts) t))

    _ -> go 0 e00
 where
  PK{..} = pk

  go i e0 = case e0 of
    App{} | (f,xs) <- collectArgs e0 ->
      parensIf (i > 0) $
        go 0 f $\ fsep (map (go 1) xs)
    Lcl x _   -> pp_symb x
    Gbl x _ _ -> pp_symb x
    Lit x     -> integer x
    String s  -> text (show s)
    Case e Nothing alts ->
      parensIf (i > 0) $
        end $
          (("match" $\ ppExpr pk e) $\ "with") $$
          (separating vcat (repeat "|") (map (ppAlt pk) alts))
    Lam x t e ->
      parensIf (i > 0) $
        ("\\" $\ (parens (pp_symb x <+> ":" $\ ppType pk 0 t))) <+> "." $\ ppExpr pk e
    Let (fn:fns) e ->
      parensIf (i > 0) $
        ("let" $\ ppFuns pk [fn]) $\ ("in" $\ ppExpr pk (Let fns e))
    Let []       e -> ppExpr pk e

csv' :: [Doc] -> Doc
csv' [] = empty
csv' xs = parens (sep (punctuate "," xs))

csv'' :: [Doc] -> Doc
csv'' [] = empty
csv'' xs = sep (punctuate "," xs)

ppAlt :: Eq a => PK a -> Alt a -> Doc
ppAlt pk (pat,rhs) = ppPat pk pat <+> "->" $\ ppExpr pk rhs

ppPat :: Eq a => PK a -> Pattern a -> Doc
ppPat pk pat = case pat of
    Default            -> "_"
    ConPat c _ty ts bs -> pp_symb c $\ fsep (map (pp_symb . fst) bs)
    LitPat i           -> integer i
  where PK{..} = pk

{-
-- collect arrows arguments , and print them as a tuple with *
ppTopType :: Eq a => PK a -> Type a -> Doc
ppTopType pk t = case collectArrTy t of
    ([],r) -> ppType pk r
    (as,r) -> tuple (map (ppType pk) as) <+> ">" $\ ppType pk r
-}

ppTyVar :: Eq a => PK a -> a -> Doc
ppTyVar PK{..} x = "'" <> pp_symb x

ppType :: Eq a => PK a -> Int -> Type a -> Doc
ppType pk i t0 = case t0 of
    TyVar x     -> ppTyVar pk x
    ArrTy t1 t2 -> parens (ppType pk 0 t1 <+> "->" $\ ppType pk 0 t2)
    TyCon tc ts -> parensIf (i > 0 && not (null ts)) $ pp_symb tc $\ fsep (map (ppType pk 1) ts)
    Integer     -> "int"
  where PK{..} = pk
