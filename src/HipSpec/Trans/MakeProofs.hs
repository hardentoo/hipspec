{-# LANGUAGE RecordWildCards,NamedFieldPuns,TypeOperators,
             ParallelListComp,ViewPatterns #-}
module HipSpec.Trans.MakeProofs (runMakerM, makeProofs, translateLemma) where

import Data.List (nub)

import Induction.Structural

import HipSpec.Trans.ProofDatatypes
import HipSpec.Trans.Theory
import HipSpec.Trans.Property as Prop
import HipSpec.Trans.Types
import HipSpec.Trans.TypeGuards
import HipSpec.Params

import Control.Concurrent.STM.Promise.Tree

import Halo.FOL.Abstract hiding (Term)
import Halo.ExprTrans
import Halo.Monad
import Halo.Util
import Halo.Shared
import Halo.Subtheory

import Data.Maybe (mapMaybe)

import Control.Monad.Reader
import Control.Monad.State
import Control.Monad.Error

import qualified CoreSyn as C
import CoreSyn (CoreExpr)
import CoreSubst
import UniqSupply
import DataCon
import Type
import Var
import Id
import Outputable hiding (equals,text)
import qualified Outputable as Outputable

translateLemma :: Prop -> HaloM HipSpecSubtheory
translateLemma lemma@Prop{..} = do
    (tr_lem,ptrs) <- capturePtrs equals
    return $ Subtheory
        { provides    = Specific (Lemma propRepr)
        , depends     = map Function propFunDeps ++ ptrs
        , description = "Lemma " ++ propRepr ++ "\n" ++
                        "dependencies: " ++ unwords (map idToStr propFunDeps)
        , formulae    = [tr_lem]
        }
  where
    equals :: HaloM Formula'
    equals = do
        (lhs,rhs) <- trEquality propEquality
        assums <- mapM trEquality' propAssume
        return $ foralls $ (min' lhs \/ min' rhs) ==> (assums ===> lhs === rhs)

type MakerM = StateT UniqSupply HaloM

runMakerM :: HaloEnv -> UniqSupply -> MakerM a -> ((a,[String]),UniqSupply)
runMakerM env us mm
    = case runHaloMsafe env (runStateT mm us) of
        (Right ((hm,us')),msg) -> ((hm,msg),us')
        (Left err,_msg)
            -> error $ "Halo.Trans.MakeProofs.runMakerM, halo says: " ++ err

trEquality :: Equality -> HaloM (Term',Term')
trEquality (e1 :== e2) = liftM2 (,) (trExpr e1) (trExpr e2)

trEquality' :: Equality -> HaloM Formula'
trEquality' = liftM (uncurry (===)) . trEquality

-- One subtheory with a conjecture with all dependencies
type ProofProperty = Property HipSpecSubtheory
type ProofTree     = Tree ProofProperty

makeProofs :: Params -> Prop -> MakerM ProofTree
makeProofs Params{methods,indvars,indparts,indhyps,inddepth} prop@Prop{..}
    = requireAny <$>
        (sequence (mapMaybe induction induction_coords) `catchError` \err -> do
          lift $ cleanUpFailedCapture
          return [])
  where
    induction_coords :: [[Int]]
    induction_coords = nub $
        [ concat (replicate depth var_ixs)
        -- ^ For each variable, repeat it to the depth
        | var_ixs <- var_pow
        -- ^ Consider all sets of variables
        , length var_ixs <= indvars
        , 'p' `elem` methods || length var_ixs > 0
        -- ^ Don't do induction on too many variables
        , depth <- [start_depth..stop_depth]
        ]
      where
        var_indicies :: [Int]
        var_indicies = zipWith const [0..] propVars

        var_pow :: [[Int]]
        var_pow = filterM (const [False,True]) var_indicies

        start_depth | 'p' `elem` methods = 0
                    | otherwise          = 1
        stop_depth  | 'i' `elem` methods = inddepth
                    | otherwise          = 0

    induction :: [Int] -> Maybe (MakerM ProofTree)
    induction coords = do
        let obligs = subtermInduction tyEnv propVars coords

        -- If induction on these variables with this depth gives too many
        -- obligations, then do not do this induction, return Nothing
        guard (length obligs <= indparts)

        -- Some parts give very many hypotheses. If this is the case,
        -- we cruelly drop some of the first weak ones
        let dropHyps oblig = oblig
                { hypotheses = take indhyps (reverse $ hypotheses oblig) }

        return $ fmap requireAll $ do

            -- Rename the variables
            obligs' <- fst <$> unTagMapM makeVar obligs

            forM obligs' $ \ oblig ->  do

                ((commentary,fs),ptrs) <- lift $ capturePtrs $ trObligation prop (dropHyps oblig)

                return $ Leaf $ Property prop $ Subtheory
                    { provides    = Specific Conjecture
                    , depends     = map Function propFunDeps ++ ptrs
                    , description = "Conjecture for " ++ propName ++ "\n" ++ commentary
                    , formulae    = fs
                    }

trTerm :: Term DataCon Var -> CoreExpr
trTerm (Var x)    = C.Var x
trTerm (Con c as) = foldl C.App (C.Var (dataConWorkId c)) (map trTerm as)
trTerm (Fun f as) = foldl C.App (C.Var f) (map trTerm as)

ghcStyle :: Style DataCon Var Type
ghcStyle = Style
    { linc = text . showOutputable
    , linv = text . showOutputable
    , lint = text . showOutputable
    }

data Loc = Hyp | Concl

makeVar :: Tagged Var -> MakerM Var
makeVar (v :~ i) = do
    (u,us) <- takeUniqFromSupply <$> get
    put us
    return (setVarUnique v u)

trObligation :: Prop -> Obligation DataCon Var Type -> HaloM (String,[Formula'])
trObligation Prop{..} obligation@(Obligation skolem hyps concl) =

    local (addSkolems skolem_vars) $ do

        (tr_hyps) <- mapM trHyp hyps

        (tr_concl) <- splitFormula <$> trPred Concl concl

        return
            ("Proof by structural induction\n" ++
                render (linObligation ghcStyle obligation)
            ,tr_concl ++ tr_hyps ++ mapMaybe typeGuardSkolem skolem_vars
            )

  where

    skolem_vars = map fst skolem

    trPred :: Loc -> [Term DataCon Var] -> HaloM Formula'
    trPred loc tms = do
        (lhs,rhs) <- trEquality propEquality'
        assums <- mapM trEquality' propAssume'
        return $ case loc of
                Hyp   -> min' lhs \/ min' rhs ==> (assums ===> lhs === rhs)
                Concl -> ands $ [minrec rhs,minrec lhs,rhs =/= lhs] ++ assums
      where
        s = extendIdSubstList emptySubst
                [ (v,trTerm t) | (v,_) <- propVars | t <- tms ]

        propEquality':propAssume' = flip map (propEquality:propAssume) $ \ eq -> case eq of
            e1 :== e2 -> substExpr (Outputable.text "trPred") s e1 :==
                         substExpr (Outputable.text "trPred") s e2

    trHyp :: Hypothesis DataCon Var Type -> HaloM Formula'
    trHyp (_,tms) = foralls <$> trPred Hyp tms


