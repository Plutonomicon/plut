{-# LANGUAGE ConstraintKinds #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE UndecidableInstances #-}
{-# OPTIONS_GHC -Wno-orphans #-}

module Pluton.Types.Builtin.List
  ( -- * List type
    PList (..),

    -- * List construction
    cons,
    nil,
    mkList,
    singleton,
    append,

    -- * List access
    head,
    contains,
    atIndex,
  )
where

import Data.Proxy
import Plutarch
import Plutarch.Bool
import Plutarch.Integer (PInteger)
import Plutarch.Prelude
import Pluton.Types.Builtin
import Pluton.Types.Builtin qualified as B
import Pluton.Types.Builtin.Uni
import PlutusCore qualified as PLC
import Prelude hiding (head)

data PList a s
  = PNil
  | PCons (Term s a) (Term s (PList a))

instance PDefaultUni (a :: k -> Type) => PlutusType (PList a) where
  type PInner (PList a) _ = PList a
  pcon' PNil =
    punsafeConstant $
      PLC.Some $
        PLC.ValueOf
          ( PLC.DefaultUniList $
              PLC.knownUniOf $ Proxy @(PDefaultUniType a)
          )
          []
  pcon' (PCons x xs) = B.pBuiltinFun @'PLC.MkCons @'[a] # x # xs
  pmatch' = pmatchList

type instance PBuiltinFunType 'PLC.MkCons '[a] = a :--> PList a :--> PList a

type instance PBuiltinFunType 'PLC.NullList '[a] = PList a :--> PBool

type instance PBuiltinFunType 'PLC.HeadList '[a] = PList a :--> a

type instance PBuiltinFunType 'PLC.TailList '[a] = PList a :--> PList a

pmatchList :: forall k (s :: k) (a :: k -> Type) (b :: k -> Type). Term s (PList a) -> (PList a s -> Term s b) -> Term s b
pmatchList list f =
  plet (B.pBuiltinFun @'PLC.NullList @'[a] # list) $ \isEmpty ->
    pif
      (punsafeCoerce isEmpty)
      (f PNil)
      $ plet
        (B.pBuiltinFun @'PLC.HeadList @'[a] # list)
        ( \head ->
            plet (B.pBuiltinFun @'PLC.TailList @'[a] # list) $ \tail ->
              f $ PCons head tail
        )

cons :: forall k (s :: k) (a :: k -> Type). PDefaultUni a => Term s a -> Term s (PList a) -> Term s (PList a)
cons x xs = pcon' $ PCons x xs

nil :: forall k (s :: k) (a :: k -> Type). PDefaultUni a => Term s (PList a)
nil = pcon' PNil

-- | Build a polymorphic list from a list of PLC terms.
mkList :: forall k (s :: k) (a :: k -> Type). PDefaultUni a => [Term s a] -> Term s (PList a)
mkList = \case
  [] -> nil
  (x : xs) -> cons x (mkList xs)

-- | Return the head of a list; fails on empty list.
head :: forall k (s :: k) (c :: k -> Type). Term s (PList c) -> Term s c
head list =
  pmatchList list $ \case
    PNil -> perror
    PCons x _ -> x

-- | Create a singleton list
singleton :: PDefaultUni a => Term s a -> Term s (PList a)
singleton x =
  pcon' (PCons x $ pcon' PNil)

-- | Return True if the list contains the given element.
contains :: (PEq a, PDefaultUni a) => ClosedTerm (PList a :--> a :--> PBool)
contains =
  pfix #$ plam $ \self list k ->
    pmatch' list $ \case
      PNil ->
        pcon PFalse
      PCons x xs ->
        pif
          (k #== x)
          (pcon PTrue)
          (self # xs # k)

-- | Return the element at given index; fail otherwise.
atIndex :: PDefaultUni a => ClosedTerm (PInteger :--> PList a :--> a)
atIndex =
  pfix #$ plam $ \self n' list ->
    pmatch' list $ \case
      PNil ->
        perror
      PCons x xs ->
        pif
          (n' #== 0)
          x
          (self # (n' - 1) # xs)

-- | Append two lists
append :: PDefaultUni a => ClosedTerm (PList a :--> PList a :--> PList a)
append =
  pfix #$ plam $ \self list1 list2 ->
    pmatch' list1 $ \case
      PNil ->
        list2
      PCons x xs ->
        pcon' (PCons x $ self # xs # list2)
