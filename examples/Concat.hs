{-# LANGUAGE DeriveDataTypeable #-}
module Concat where

import Prelude hiding ((++),length,(+),map,sum,concat)
import HipSpec

length :: [a] -> Nat
length []     = Z
length (_:xs) = S (length xs)

sum :: [Nat] -> Nat
sum []     = Z
sum (x:xs) = x + sum xs

(++) :: [a] -> [a] -> [a]
(x:xs) ++ ys = x:(xs ++ ys)
[]     ++ ys = ys

concat :: [[a]] -> [a]
concat xss = [ x | xs <- xss, x <- xs ]

map :: (a -> b) -> [a] -> [b]
map f xs = [ f x | x <- xs ]

sig :: [Sig]
sig = [ vars ["m", "n", "o"]          (undefined :: Nat)
      , vars ["x", "y", "z"]          (undefined :: A)
      , vars ["xs", "ys", "zs"]       (undefined :: [A])
      , vars ["xss", "yss", "zss"]    (undefined :: [[A]])
      , vars ["xsss", "ysss", "zsss"] (undefined :: [[[A]]])

      , fun0 "Z"                Z
      , fun1 "S"                S
      , fun2 "+"                (+)

      -- These three for {sum (map length xss) = length (join xss)}
      , fun1 "sum"              (sum :: [Nat] -> Nat)
      , blind0 "length"         (length :: [A] -> Nat)
      , fun2 "map"              (map :: ([A] -> Nat) -> [[A]] -> [Nat])

      , fun0 "[]"               ([] :: [A])
      , fun2 ":"                ((:) :: A -> [A] -> [A])
      , fun2 "++"               ((++) :: [A] -> [A] -> [A])
      , fun1 "length"           (length :: [A] -> Nat)


      , fun0 "[]"               ([] :: [[A]])
      , fun2 ":"                ((:) :: [A] -> [[A]] -> [[A]])
      , fun2 "++"               ((++) :: [[A]] -> [[A]] -> [[A]])
      , fun1 "length"           (length :: [[A]] -> Nat)

      , fun0 "[]"               ([] :: [[[A]]])
      , fun2 ":"                ((:) :: [[A]] -> [[[A]]] -> [[[A]]])
      , fun2 "++"               ((++) :: [[[A]]] -> [[[A]]] -> [[[A]]])
      , fun1 "length"           (length :: [[[A]]] -> Nat)

      , fun2 "map"              (map :: ([[A]] -> [A]) -> [[[A]]] -> [[A]])
      , fun2 "map"              (map :: ([A] -> A) -> [[A]] -> [A])
      , blind0 "concat"         (concat :: [[A]] -> [A])
      , blind0 "concat"         (concat :: [[[A]]] -> [[A]])
      , fun1 "concat"           (concat :: [[A]] -> [A])
      , fun1 "concat"           (concat :: [[[A]]] -> [[A]])
      ]

data Nat = Z | S Nat deriving (Eq,Ord,Show,Typeable)

infixl 6 +

(+) :: Nat -> Nat -> Nat
S n + m = S (n + m)
Z   + m = m

instance Enum Nat where
  toEnum 0 = Z
  toEnum n = S (toEnum (pred n))
  fromEnum Z = 0
  fromEnum (S n) = succ (fromEnum n)

instance Arbitrary Nat where
  arbitrary = sized $ \ s -> do
    x <- choose (0,round (sqrt (toEnum s) :: Double))
    return (toEnum x)

