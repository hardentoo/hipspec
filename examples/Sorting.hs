{-# LANGUAGE DeriveDataTypeable #-}
module Sorting where

import Prelude (Bool(..),undefined,Ordering(..), (&&), otherwise, not, fmap, Eq, Ord)
import HipSpec
import Nat
import Test.QuickSpec.Signature
import Test.QuickSpec
import Test.QuickSpec.Prelude
import Test.QuickCheck hiding ((==>))
import GHC.Types
import Data.Typeable

data List = Nil | Cons Nat List deriving (Typeable, Eq, Ord)

instance Arbitrary List where
  arbitrary = fmap fromList arbitrary
    where
      fromList [] = Nil
      fromList (x:xs) = Cons x (fromList xs)

(<=) :: Nat -> Nat -> Bool
Z   <= _   = True
S _ <= Z   = False
S x <= S y = x <= y

count :: Nat -> List -> Nat
count n Nil = Z
count n (Cons x xs)
  | n <= x && x <= n = S (count n xs)
  | otherwise = count n xs

isort :: List -> List
isort Nil = Nil
isort (Cons x xs) = insert x (isort xs)

insert :: Nat -> List -> List
insert n Nil = Cons n Nil
insert n (Cons x xs)
  | n <= x = Cons n (Cons x xs)
  | otherwise = Cons x (insert n xs)

merge (Cons x xs) (Cons y ys)
    | x <= y = Cons x (merge xs (Cons y ys))
    | True   = Cons y (merge (Cons x xs) ys)
merge xs Nil = xs
merge Nil ys = ys

sorted :: List -> Bool
sorted (Cons x (Cons y xs))
  | x <= y = sorted (Cons y xs)
  | otherwise = False
sorted _        = True

-- To run:
-- hipspec Sorting --auto --extra-trans=isort,count,sorted --cg --cond-name=sorted --cond-count=1 -t0.05
prop_sort_sorted xs = sorted (isort xs) =:= True
prop_sort_permutation xs x = count x xs =:= count x (isort xs)
