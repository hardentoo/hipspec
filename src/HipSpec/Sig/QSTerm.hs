{-# LANGUAGE ParallelListComp, ViewPatterns, PatternGuards, ScopedTypeVariables, RecordWildCards, NamedFieldPuns #-}
-- | Translating from QuickSpec -> Core
--
--   There are no type variables here, properties are to be generalised in a
--   later pass.
module HipSpec.Sig.QSTerm (eqToProp) where

import Test.QuickSpec.Term as T
import Test.QuickSpec.Equation as E
import Test.QuickSpec.Signature (disambiguate, variables)
import Test.QuickSpec.Utils.TypeRel hiding (lookup)

import HipSpec.Read (SigInfo(..))
import HipSpec.Sig.Symbols
import HipSpec.Utils
import HipSpec.Property as P
import qualified HipSpec.Lang.Simple as S

import HipSpec.Params

import HipSpec.Lang.CoreToRich as CTR

import Data.List (intercalate)

import HipSpec.Id

termToExpr :: SymbolMap -> Term -> S.Expr Id
termToExpr sm = go
  where
    go t = case t of
        T.App e1 e2 -> S.App (go e1) (go e2)
        T.Var s     -> uncurry S.Lcl (lookupVar sm s)
        T.Const s   -> lookupCon sm s

eqToProp :: Params -> SigInfo -> Integer -> Equation -> Property Equation
eqToProp Params{cond_name,isabelle_mode} SigInfo{..} i eq@(e1 E.:=: e2) = Property
    { prop_name      = final_repr
    , prop_id        = QSOrigin "" i
    , prop_origin    = Equation eq
    , prop_tvs       = []
    , prop_vars      = map (lookupVar symbol_map) occuring_vars
    , prop_goal      = goal
    , prop_assums    = [ mk_assum x | x <- precond_vars ]
    , prop_repr      = final_repr
    , prop_var_repr  = map show occuring_vars
    }
  where
    mk_assum x = P.equalsTrue
        (S.Gbl v t ts `S.App` uncurry S.Lcl (lookupVar symbol_map x))
      where
        Just mono_ty = cond_mono_ty
        Just cd_id   = cond_id
        (v,t,ts) = translateId (either error id (CTR.trType mono_ty)) cd_id

    repr = show_eq e1 ++ eqls ++ show_eq e2
      where
        show_eq = show . mapVars disambig . mapConsts (on_name g)

        on_name h s = s { name = h (name s) }

        g x = case lookup x isabelleFunctionNames of
            Just y  | isabelle_mode -> y
            _                       -> x

        eqls | isabelle_mode = " = "
             | otherwise     = " == "

    final_repr = show_precond precond_vars repr

    raw_occuring_vars :: [Symbol]
    raw_occuring_vars = nubSorted (vars e1 ++ vars e2)

    disambig :: Symbol -> Symbol
    disambig = disambiguate sig' (vars e1 ++ vars e2)
      where
        sig' = sig { variables = mapValues (mapVariable delBackquote) (variables sig) }

    occuring_vars :: [Symbol]
    occuring_vars = map disambig raw_occuring_vars

    precond_vars :: [Symbol]
    precond_vars = map disambig (filter isBackquoted raw_occuring_vars)

    term_to_expr = termToExpr symbol_map

    goal = term_to_expr e1 P.:=: term_to_expr e2

    show_precond [] u = u
    show_precond xs u = intercalate conj [ cond_name ++ " " ++ show x | x <- xs ] ++ " ==> " ++ u
      where
        conj | isabelle_mode = " & "
             | otherwise     = " && "

isBackquoted :: Symbol -> Bool
isBackquoted a = case name a of
    '`':_ -> True
    _     -> False

delBackquote :: Symbol -> Symbol
delBackquote a = case name a of
    '`':xs -> a { name = xs }
    _      -> a

isabelleFunctionNames :: [(String, String)]
isabelleFunctionNames =
  [("&&", "HOL.conj"),
   (":", "#"),
   ("++", "@"),
   ("reverse", "rev"),
   ("plus_nat", "Groups.plus_class.plus"),
   ("Zero_nat", "Groups.zero_class.zero"),
   ("one_nat", "Groups.one_class.one")]
