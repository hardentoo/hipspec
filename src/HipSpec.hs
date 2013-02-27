{-# LANGUAGE RecordWildCards #-}
module HipSpec (hipSpec, module Test.QuickSpec, fileName) where

import Test.QuickSpec
import Test.QuickSpec.Term hiding (depth, symbols)
import Test.QuickSpec.Main hiding (definitions)
import Test.QuickSpec.Equation
import Test.QuickSpec.Generate
import Test.QuickSpec.Signature
import Test.QuickSpec.Utils.Typed
import Test.QuickSpec.Reasoning.NaiveEquationalReasoning
    ((=?=), unify, execEQ, evalEQ, initial)

import HipSpec.Trans.Theory
import HipSpec.Trans.Property hiding (equal)
import HipSpec.Trans.QSTerm
import HipSpec.Init
import HipSpec.MakeInvocations
import HipSpec.Monad hiding (equations)
import HipSpec.MainLoop
import HipSpec.Heuristics.Associativity

import Prelude hiding (read)
import Halo.Util
import Halo.Subtheory
import Halo.FOL.RemoveMin

import Data.List
import Data.Ord
import Data.Maybe
import qualified Data.Map as M

import Control.Monad

import Language.Haskell.TH

import Data.Monoid (mappend)

import Data.Aeson (encode)
import qualified Data.ByteString.Lazy as B

import Text.Printf

-- Main library ---------------------------------------------------------------

fileName :: ExpQ
fileName = location >>= \(Loc f _ _ _ _) -> stringE f

hipSpec :: Signature a => FilePath -> a -> IO ()
hipSpec file sig0 = runHS $ do

    writeMsg Started

    let sig = signature sig0 `mappend` withTests 100

        showEq :: Equation -> String
        showEq = showEquation sig

        showEqs :: [Equation] -> [String]
        showEqs = map showEq

        showProperty :: Property -> String
        showProperty = showEq . propQSTerms

        showProperties :: [Property] -> [String]
        showProperties = map showProperty

        printNumberedEqs :: [Equation] -> IO ()
        printNumberedEqs eqs = forM_ (zip [1 :: Int ..] eqs) $ \(i, eq) ->
            printf "%3d: %s\n" i (showEq eq)

    processFile file $ \ (props,str_marsh) -> do

        theory <- getTheory
        Params{..} <- getParams

        writeMsg FileProcessed

        let getFunction s = case s of
                Subtheory (Function v) _ _ _ ->
                    let Subtheory _ _ _ fs = removeMinsSubthy s
                    in  Just (v,fs)
                _ -> Nothing

            func_map = M.fromList (mapMaybe getFunction (subthys theory))

            lookup_func x = fromMaybe [] (M.lookup x func_map)

            def_eqs = definitionalEquations str_marsh lookup_func sig

        when definitions $ liftIO $ do
            putStrLn "\nDefinitional equations:"
            printNumberedEqs def_eqs

        classes <- liftIO $ fmap eraseClasses (generate (const totalGen) sig)

        let eq_order eq = (assoc_important && not (eqIsAssoc eq), eq)
            swapEq (t :=: u) = u :=: t

            classToEqs :: [[Tagged Term]] -> [Equation]
            classToEqs = sortBy (comparing (eq_order . (swap_repr ? swapEq)))
                       . if quadratic
                              then sort . map (uncurry (:=:)) .
                                   concatMap (uniqueCartesian . map erase)
                              else equations

            univ      = map head classes
            reps      = map (erase . head) classes
            pruner    = prune ctx0 reps
            prunedEqs = pruner (equations classes)
            eqs       = prepend_pruned ? (prunedEqs ++) $ classToEqs classes

            ctx_init  = initial (maxDepth sig) (symbols sig) univ
            ctx0      = execEQ ctx_init (mapM_ unify def_eqs)

            definition (t :=: u) = evalEQ ctx0 (t =?= u)

            qsprops   = filter (not . definition . propQSTerms)
                      $ map (eqToProp str_marsh) eqs

        when quickspec $ liftIO $ writeFile (file ++ "_QuickSpecOutput.txt") $
            "All stuff from QuickSpec:\n" ++
            intercalate "\n" (map show (classToEqs classes))

        writeMsg $ QuickSpecDone (length classes) (length eqs)

        liftIO $ putStrLn "Starting to prove..."

        (qslemmas,qsunproved,ctx) <- deep showEq ctx0 qsprops

        when explore_theory $ do
            let provable (t :=: u) = evalEQ ctx (t =?= u)
                explored_theory    = pruner $ filter provable (equations classes)
            writeMsg $ ExploredTheory (showEqs explored_theory)
            liftIO $ do
                putStrLn "\nExplored theory (proved correct):"
                printNumberedEqs explored_theory

        writeMsg StartingUserLemmas

        (unproved,proved) <- parLoop props qslemmas

        writeMsg $ Finished
            (filter (`notElem` map propName qslemmas) $ map propName proved)
            (map propName unproved)
            (map propName qslemmas)
            (showProperties qsunproved)

        printInfo unproved proved

        unless dont_print_unproved $ liftIO $
            putStrLn $ "Unproved from QuickSpec: " ++ csv (showProperties qsunproved)

        case json of
            Just json_file -> do
                msgs <- getMsgs
                liftIO $ B.writeFile json_file (encode msgs)
            Nothing -> return ()

