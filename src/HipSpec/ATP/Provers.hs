{-# LANGUAGE DeriveDataTypeable #-}
module HipSpec.ATP.Provers where

import Data.Maybe
import Data.List
import Data.Data

{-# ANN module "HLint: ignore Use camelCase" #-}

-- | The names of the different supported theorem provers
data ProverName = AltErgo | MonoAltErgo | Vampire | Z3 | CVC4
  deriving (Eq,Ord,Enum,Bounded,Show,Data,Typeable)

defaultProverNames :: [ProverName]
defaultProverNames = [Z3]

proverFromName :: ProverName -> Prover
proverFromName p = case p of
    AltErgo     -> altErgo
    MonoAltErgo -> monoAltErgo
    Vampire     -> vampire
    Z3          -> z3
    CVC4        -> cvc4

proversFromNames :: [ProverName] -> [Prover]
proversFromNames = map proverFromName

allProverNames :: [ProverName]
allProverNames = [minBound..maxBound]

-- | A record of information concerning a theorem prover
data Prover = Prover
    { prover_cmd            :: String
    -- ^ System command to createProcess
    , prover_desc           :: String
    -- ^ Description in the parameter list
    , prover_name           :: ProverName
    -- ^ Refers to its name
    , prover_cannot_stdin   :: Bool
    -- ^ This prover cannot read from stdin, so instead read from file
    , prover_args           :: String -> Double -> [String]
    -- ^ Given file name (if prover_cannot_stdin)
    --   and timeout in secs, args to createProcess
    , prover_process_output :: String -> Maybe Bool
    -- ^ Processes the output and time and gives a result
    , prover_suppress_errs  :: Bool
    -- ^ Should we ignore standard error from this prover?
    , prover_parse_lemmas   :: Maybe (String -> [Int])
    -- ^ This prover's method of parsing lemmas
    , prover_input_format   :: InputFormat
    }

-- | Input formats
data InputFormat = AltErgoFmt | AltErgoMonoFmt | MonoTFF | SMT
  deriving (Eq,Ord,Show)

extension :: InputFormat -> String
extension fmt = case fmt of
    AltErgoFmt     -> "mlw"
    AltErgoMonoFmt -> "mlw"
    MonoTFF        -> "tff"
    SMT            -> "smt"

altErgo :: Prover
altErgo = Prover
    { prover_cmd            = "alt-ergo"
    , prover_desc           = "Alt-Ergo"
    , prover_name           = AltErgo
    , prover_cannot_stdin   = True
    , prover_args           = \ f _t -> [f,{- "-timelimit",showCeil t, -} "-triggers-var"]
    , prover_process_output = searchOutput
        [("Valid",proven),("I don't know",failure) ]
    , prover_suppress_errs  = False
    , prover_parse_lemmas   = Nothing
    , prover_input_format   = AltErgoFmt
    }

monoAltErgo :: Prover
monoAltErgo = altErgo
    { prover_input_format = AltErgoMonoFmt
    , prover_name         = MonoAltErgo
    }

vampire :: Prover
vampire = Prover
    { prover_cmd            = "vampire_rel"
    , prover_desc           = "Vampire"
    , prover_name           = Vampire
    , prover_cannot_stdin   = True
    , prover_args           = \ f t -> [f,"-t",showCeil t,"-mode","casc"]
    , prover_process_output = searchOutput
        [("Unsatisfiable",proven),("Theorem",proven)
        ,("Timeout",failure),("Satisfiable",failure)
        ]
    , prover_suppress_errs  = False
    , prover_parse_lemmas   = Nothing
    , prover_input_format   = MonoTFF
    }

z3 :: Prover
z3 = Prover
    { prover_cmd            = "z3"
    , prover_desc           = "Z3"
    , prover_name           = Z3
    , prover_cannot_stdin   = False
    , prover_args           = \ _f _t -> ["-smt2","-nw","/dev/stdin"]
    , prover_process_output = searchOutput
        [("unsat",proven)
--        ,("sat",failure)
        ]
    , prover_suppress_errs  = False
    , prover_parse_lemmas   = Nothing
    , prover_input_format   = SMT
    }

cvc4 :: Prover
cvc4 = Prover
    { prover_cmd            = "cvc4"
    , prover_desc           = "CVC4"
    , prover_name           = CVC4
    , prover_cannot_stdin   = False
    , prover_args           = \ _f t -> ["--lang=smt2","--tlimit=" ++ showCeil (t*1000)]
    , prover_process_output = searchOutput
        [("unsat",proven)
        ,("unknown",failure)
        ]
    , prover_suppress_errs  = False
    , prover_parse_lemmas   = Nothing
    , prover_input_format   = SMT
    }


proven,failure :: Maybe Bool
proven  = Just True
failure = Just False

showCeil :: Double -> String
showCeil = show . (ceiling :: Double -> Integer)

-- Should really use something more efficient than isInfixOf
searchOutput :: [(String,Maybe Bool)] -> String -> Maybe Bool
searchOutput []         _      = Nothing
searchOutput ((s,r):xs) output
    | s `isInfixOf` output = r
    | otherwise            = searchOutput xs output

proverCanSpecifyLemmas :: Prover -> Bool
proverCanSpecifyLemmas = isJust . prover_parse_lemmas

