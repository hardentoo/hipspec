module Main where

import Prelude(undefined,Bool(..),IO,flip,($))

import HipSpec.Prelude
import HipSpec
import Definitions
import Properties

main :: IO ()
main = hipSpec "Part52.hs"
    [ vars ["x", "y", "z"] (undefined :: Nat)
    , vars ["xs", "ys", "zs"] (undefined :: [Nat])
    -- Constructors
    , "Z" `fun0` Z
    , "S" `fun1` S
    , "[]" `fun0` ([] :: [Nat])
    , ":"  `fun2` ((:) :: Nat -> [Nat] -> [Nat])
    -- Functions
    , "count" `fun2` ((count) :: Nat -> [Nat] -> Nat)
    , "==" `fun2` (==)
    , "rev" `fun1` ((rev) :: [Nat] -> [Nat])
    , "++" `fun2` ((++) :: [Nat] -> [Nat] -> [Nat])
    ]

to_show = (prop_52)