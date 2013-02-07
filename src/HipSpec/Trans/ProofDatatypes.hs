{-# LANGUAGE DeriveFunctor #-}
module HipSpec.Trans.ProofDatatypes where

import Data.Function
import Data.List

import Var

import HipSpec.Trans.Theory (HipSpecContent,HipSpecSubtheory)

import Halo.Subtheory
import Halo.FOL.Abstract

import HipSpec.Trans.Property

data Property a = Property
    { prop_prop    :: Prop
    , prop_content :: a
    }
  deriving (Functor,Show)

data Proof a = Induction
    { ind_coords  :: [Int]
    , ind_oblig   :: Int
    , ind_obligs  :: Int
    , ind_content :: a
    -- ^ This will be a theory, TPTP string or prover results
    }
  deriving (Functor)

{-
instance Semigroup (Proof a) where
    Induction cs o os a <> Induction cs' o' s' a =
        case cs
-}


{-
data ProofMethod
    = Plain
    | Induction { coords :: [Int] }
  deriving (Eq,Ord)

instance Show ProofMethod where
    show Plain          = "plain"
    show (Induction vs) = "structural induction on " ++ unwords (map show vs)

proofMethodFile :: ProofMethod -> String
proofMethodFile pt = case pt of
    Plain        -> "plain"
    Induction vs -> intercalate "_" (map show vs)

type Property  = PropertyMatter [Part]
type Part      = PartMatter     ([HipSpecContent],[HipSpecSubtheory],[Particle])
type Particle  = ParticleMatter [Clause']

data PropertyMatter m = Property
    { propName   :: String
    -- ^ The identifier of the property
    , propCode   :: String
    -- ^ Some representiation
    , propMatter :: m
    -- ^ The meat of the property
    }
  deriving (Show,Functor)

instance Eq (PropertyMatter m) where
  (==) = (==) `on` propName

instance Ord (PropertyMatter m) where
  compare = compare `on` propName

data PartMatter m = Part
    { partMethod    :: ProofMethod
    , partMatter    :: m
    }
  deriving (Show,Functor)

instance Eq (PartMatter m) where
  (==) = (==) `on` partMethod

instance Ord (PartMatter m) where
  compare = compare `on` partMethod

data ParticleMatter m = Particle
    { particleDesc   :: String
    , particleMatter :: m
    }
  deriving (Eq,Ord,Show,Functor)

extendPart :: [HipSpecSubtheory] -> Part -> Part
extendPart st' (Part n (vs,st,p)) = Part n (vs,st++st',p)
-}
