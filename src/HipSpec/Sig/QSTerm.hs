{-# LANGUAGE ParallelListComp, ViewPatterns, PatternGuards, ScopedTypeVariables, RecordWildCards #-}
-- | Translating from QuickSpec -> Core
--
--   There are no type variables here, properties are to be generalised in a
--   later pass.
module HipSpec.Sig.QSTerm (eqToProp) where

import Test.QuickSpec.Term as T
import Test.QuickSpec.Equation as E
import Test.QuickSpec.Signature (disambiguate)

import HipSpec.Read (SigInfo(..))
import HipSpec.Sig.Symbols
import HipSpec.Utils
import HipSpec.Property as P
import qualified HipSpec.Lang.Simple as S

import HipSpec.Lang.CoreToRich as CTR

-- import HipSpec.Theory
import HipSpec.Id

termToExpr :: SymbolMap -> Term -> S.Expr Id
termToExpr sm = go
  where
    go t = case t of
        T.App e1 e2 -> S.App (go e1) (go e2)
        T.Var s     -> uncurry S.Lcl (lookupVar sm s)
        T.Const s   -> lookupCon sm s

eqToProp :: SigInfo -> Integer -> Equation -> Property Equation
eqToProp SigInfo{..} i eq@(e1 E.:=: e2) = Property
    { prop_name      = repr
    , prop_id        = QSOrigin "" i
    , prop_origin    = Equation eq
    , prop_tvs       = []
    , prop_vars      = map (lookupVar symbol_map) occuring_vars
    , prop_goal      = goal
    , prop_assums    = [ mk_assum x | x <- occuring_vars, isBackquoted x ]
    , prop_repr      = repr
    , prop_var_repr  = map (show . disambig) occuring_vars
    }
  where
    mk_assum x = P.equalsTrue
        (S.Gbl v t ts `S.App` uncurry S.Lcl (lookupVar symbol_map x))
      where
        Just mono_ty = cond_mono_ty
        Just cd_id   = cond_id
        (v,t,ts) = translateId (either error id (CTR.trType mono_ty)) cd_id

    repr = show (mapVars disambig e1 E.:=: mapVars disambig e2)

    disambig = disambiguate sig (vars e1 ++ vars e2)

    occuring_vars :: [Symbol]
    occuring_vars = nubSorted (vars e1 ++ vars e2)

    term_to_expr = termToExpr symbol_map

    goal = term_to_expr e1 P.:=: term_to_expr e2

    isBackquoted :: Symbol -> Bool
    isBackquoted a = case name a of
        '`':_ -> True
        _     -> False
