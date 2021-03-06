{-# LANGUAGE DeriveGeneric,RecordWildCards,DeriveFunctor,CPP,DeriveTraversable,DeriveFoldable #-}
module HipSpec.ThmLib where

import HipSpec.Property
import HipSpec.Theory
import HipSpec.ATP.Provers
import Data.Traversable
import Data.Foldable

#ifdef SUPPORT_JSON
import Data.Aeson
#endif
import GHC.Generics

import Control.Concurrent.STM.Promise.Tree
import Data.List(intercalate)

{-# ANN module "HLint: ignore Use camelCase" #-}

-- One subtheory with a conjecture with all dependencies
type ProofObligation eq = Obligation eq Subtheory
type ProofTree eq       = Tree (ProofObligation eq)

data Theorem eq = Theorem
    { thm_prop    :: Property eq
    , thm_proof   :: Proof
    , thm_lemmas  :: Maybe [Property eq]
    , thm_provers :: [ProverName]
    }
  deriving (Show,Functor)

data Proof = ByInduction { ind_vars :: [String] }
  deriving Show

definitionalTheorem :: Theorem eq -> Bool
definitionalTheorem Theorem{..} = case thm_proof of
    ByInduction{..} -> null ind_vars

data Obligation eq a = Obligation
    { ob_prop     :: Property eq
    , ob_info     :: ObInfo
    , ob_content  :: a
    -- ^ This will be a theory, TPTP string or prover results
    }
  deriving (Show,Functor,Foldable,Traversable)

data ObInfo
    = ObInduction
        { ind_coords :: [Int]
        , ind_num    :: Int
        , ind_nums   :: Int
        }
  deriving (Eq,Ord,Show,Generic)

#ifdef SUPPORT_JSON
instance ToJSON ObInfo
#endif

obInfoFileName :: ObInfo -> String
obInfoFileName (ObInduction cs n _)
    = intercalate "_" (map show cs) ++ "__" ++ show n
