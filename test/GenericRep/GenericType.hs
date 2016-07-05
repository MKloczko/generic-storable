{-#LANGUAGE GADTs         #-}
{-#LANGUAGE TypeOperators #-}
{-#LANGUAGE KindSignatures #-}
{-#LANGUAGE FlexibleInstances #-}
{-#LANGUAGE FlexibleContexts #-}
{-#LANGUAGE ScopedTypeVariables #-} 
{-#LANGUAGE InstanceSigs #-}
{-#LANGUAGE PartialTypeSignatures #-}

{-#LANGUAGE DataKinds #-}
module GenericType where
-- Test modules
import Test.QuickCheck
import Test.QuickCheck.Modifiers (NonEmptyList(..))
-- Tested modules
import Foreign.Storable.Generic.Internal

-- Test data
import Foreign.Storable.Generic.Tools
import Foreign.Storable.Generic.Instances
import Foreign.Ptr (Ptr)
import Foreign.Storable
import GHC.Generics  
import Data.Int
import Data.Proxy
import Debug.Trace
import GHC.TypeLits

import Unsafe.Coerce
-- | TestType - the basic building blocks from which
-- GStorable instances are built.
class (Arbitrary a,Eq a,GStorable a, Show a) => TestType a

instance TestType Int
instance TestType Char


-- | The wrappable type class. Wraps the type in generics.
class (Show a) => Wrappable a where
    wrapType :: a -> GenericType


-------------------
-------------------
-- | Contains the basic building blocks that generate GStorable type classes.
data BasicType where
   BasicType :: (TestType a) => a -> BasicType

instance Show BasicType where
    show (BasicType val) = show val

instance Arbitrary BasicType where
    arbitrary = do
        valInt  <- choose (minBound :: Int, maxBound :: Int)
        valChar <- choose (minBound :: Char, maxBound :: Char)
        elements [BasicType valInt, BasicType valChar]

-- | Wraps the basic type with 'M1' and 'K1' type constructors. 
-- The result is usable by the testing algorithms.
instance Wrappable BasicType where
    wrapType (BasicType val) = GenericType $ M1 $ K1 val

-- Some tricks for generics:
instance Arbitrary c     => Arbitrary (K1 i c p) where
    arbitrary = K1 <$> arbitrary
instance Arbitrary (f p) => Arbitrary (M1 i c f p) where
    arbitrary = M1 <$> arbitrary
instance (Arbitrary (f p), Arbitrary (g p)) => Arbitrary ((:*:) f g p) where
    arbitrary = (:*:) <$> (arbitrary :: Gen (f p)) <*> (arbitrary :: Gen (g p))


data MyPhantom

-- | Constains generic representations of arbitrary data-types.
-- The Show constraint is used so we can print out the badly working cases.
-- The Eq and Arbitrary one are for generating different values for the same types.
data GenericType where
   GenericType  :: (p ~ MyPhantom, Eq (f p), Arbitrary (f p), GStorable' f, Show (f p)) => f p -> GenericType

instance Arbitrary GenericType where
    arbitrary = nestedType 1

instance Show GenericType where
    show (GenericType    val) = show val

instance Wrappable GenericType where
    wrapType    (GenericType  val) = GenericType $ M1 $ K1 $ val

data NestedType (n :: Nat) = NestedType GenericType

instance (KnownNat n) => Show (NestedType n) where
    show (NestedType (GenericType val)) = type_info ++ show val
        where type_info = "NestedType " ++ (show $ natVal (Proxy :: Proxy n))

instance (KnownNat n) => Arbitrary (NestedType n) where
    arbitrary = NestedType <$> nestedType (fromIntegral $ natVal (Proxy :: Proxy n))

data NestedToType (n :: Nat) = NestedToType GenericType

instance (KnownNat n) => Show (NestedToType n) where
    show (NestedToType (GenericType val)) = type_info ++ show val
        where type_info = "NestedType " ++ (show $ natVal (Proxy :: Proxy n))

instance (KnownNat n) => Arbitrary (NestedToType n) where
    arbitrary = NestedToType <$> nestedToType (fromIntegral $ natVal (Proxy :: Proxy n))


nestedType :: Int -> Gen (GenericType)
nestedType n  = nestedType' n gen
    where gen = wrapType <$> (arbitrary :: Gen BasicType) 

nestedType' :: Int -> Gen (GenericType) -> Gen (GenericType)
nestedType' n gen 
    | n <  0 = error "GenericType.nestedType': n is less than 0"
    | n == 0 = gen
    | n > 0  = do 
        fields <- choose (1, 2*n)
        nestedType' (n-1) (wrapType <$> toGenericType <$> vectorOf fields gen) 

-- | For generating nested types with components from levels below.
nestedToType :: Int -> Gen (GenericType)
nestedToType n =do
    sublist <- suchThat (sublistOf [0..n]) (\x -> length x > 0)
    wrapType <$> toGenericType <$> mapM nestedType sublist

-- | Uses the :*: operator to construct a representation of a product type.
typeProduct :: GenericType -> GenericType -> GenericType
typeProduct (GenericType val1) (GenericType val2) = GenericType $ val1 :*: val2

-- | Wraps the ['BasicType'] and ['GenericType'] lists as needed.
toGenericType :: [GenericType] -> GenericType
toGenericType []  = error "toGenericType requires at least one type"
toGenericType [v] = v
toGenericType types = foldl1 typeProduct types

-- Simulates the K1 step for generic representations. 
instance {-#OVERLAPS#-} (GStorable' f) => GStorable' (K1 i (f p)) where
    glistSizeOf'    _ = [internalSizeOf (undefined :: f p)]
    glistAlignment' _ = [internalAlignment (undefined :: f p)]
    gpeekByteOff' [f_off] ptr off   = K1 <$> internalPeekByteOff ptr (off + f_off)
    gpeekByteOff' offs ptr off   = error "Mismatch between number of offsets and fields"
    gpokeByteOff' [f_off] ptr off (K1 v) = internalPokeByteOff ptr (off + f_off) v
    gpokeByteOff' offs ptr off v  = error "Mismatch between number of offsets and fields"
    gnumberOf'      _  = 1
