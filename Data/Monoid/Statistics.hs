{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE FlexibleInstances     #-}
{-# LANGUAGE BangPatterns          #-}
-- |
-- Module     : Data.Monoid.Statistics
-- Copyright  : Copyright (c) 2010, Alexey Khudyakov <alexey.skladnoy@gmail.com>
-- License    : BSD3
-- Maintainer : Alexey Khudyakov <alexey.skladnoy@gmail.com>
-- Stability  : experimental
-- 
module Data.Monoid.Statistics ( StatMonoid(..)
                              , evalStatistic
                                -- * Statistic monoids
                              , Count(..)
                              , Mean(..)
                              , Stdev(..)
                              , stdev, stdev', variance, mean
                                -- * Additional information
                                -- $info
                              ) where


import Data.Int     (Int8, Int16, Int32, Int64)
import Data.Word    (Word8,Word16,Word32,Word64,Word)
import Data.Monoid
import qualified Data.Foldable as F

import GHC.Float (float2Double)

-- | Monoid which corresponds to some stattics. In order to do so it
--   must be commutative. In many cases it's not practical to
--   construct monoids for each element so 'papennd' was added.
--
--   First parameter of type class is monoidal accumulator. Second is
--   type of element over which statistic is calculated. 
--
--   Statistic could be calculated with fold over sample. Since
--   accumulator is 'Monoid' such fold could be easily parralelized.
class Monoid m => StatMonoid m a where
  -- | Add one element to monoid accumulator. P stands for point in
  --   analogy for Pointed.
  -- 
  -- Must satisfy.
  -- > pappend x (pappend y mempty) == pappend x mempty `mappend` pappend y mempty
  pappend :: a -> m -> m

-- | Calculate statistic over 'Foldable'. It's implemented in terms of
--   foldl'.
evalStatistic :: (F.Foldable d, StatMonoid m a) => d a -> m
evalStatistic = F.foldl' (flip pappend) mempty


----------------------------------------------------------------
-- Data types
----------------------------------------------------------------

-- | Simplest statistics. Number of elements in the sample
newtype Count a = Count { calcCount :: a }
                  deriving Show

instance Integral a => Monoid (Count a) where
  mempty = Count 0
  (Count i) `mappend` (Count j) = Count (i + j)
  {-# INLINE mempty  #-}
  {-# INLINE mappend #-}
  
instance (Integral a) => StatMonoid (Count a) b where
  pappend _ !(Count n) = Count (n + 1)
  {-# INLINE pappend #-}
  
  
  
-- | Mean of sample. Samples of Double,Float and bui;t-in integral
--   types are supported
--
-- Numeric stability of 'mappend' is not proven.
data Mean = Mean { calcMean      :: Double -- ^ Current mean
                 , calcCountMean :: Int    -- ^ Number of entries
                 }
            deriving Show

instance Monoid Mean where
  mempty = Mean 0 0
  mappend !(Mean x n) !(Mean y k) = Mean ((x*n' + y*k') / (n' + k')) (n + k)
    where
      n' = fromIntegral n
      k' = fromIntegral k
  {-# INLINE mempty  #-}
  {-# INLINE mappend #-}

-- Add one sample elemnt to Mean
addValueToMean :: (a -> Double) -> a -> Mean -> Mean
addValueToMean f !x !(Mean m n) = Mean (m + (f x - m) / fromIntegral n') n' where n' = n+1
{-# INLINE addValueToMean #-}

-- Floating point
instance StatMonoid Mean Double where
  pappend = addValueToMean id
  {-# INLINE pappend #-}
instance StatMonoid Mean Float where
  pappend = addValueToMean float2Double
  {-# INLINE pappend #-}

-- Basic integrals
instance StatMonoid Mean Integer where
  pappend = addValueToMean fromIntegral
  {-# INLINE pappend #-}
instance StatMonoid Mean Int where
  pappend = addValueToMean fromIntegral
  {-# INLINE pappend #-}
instance StatMonoid Mean Word where
  pappend = addValueToMean fromIntegral
  {-# INLINE pappend #-}

-- Fixed size ints
instance StatMonoid Mean Int8 where
  pappend = addValueToMean fromIntegral
  {-# INLINE pappend #-}
instance StatMonoid Mean Int16 where
  pappend = addValueToMean fromIntegral
  {-# INLINE pappend #-}
instance StatMonoid Mean Int32 where
  pappend = addValueToMean fromIntegral
  {-# INLINE pappend #-}
instance StatMonoid Mean Int64 where
  pappend = addValueToMean fromIntegral
  {-# INLINE pappend #-}

-- Fixed size Words
instance StatMonoid Mean Word8 where
  pappend = addValueToMean fromIntegral
  {-# INLINE pappend #-}
instance StatMonoid Mean Word16 where
  pappend = addValueToMean fromIntegral
  {-# INLINE pappend #-}
instance StatMonoid Mean Word32 where
  pappend = addValueToMean fromIntegral
  {-# INLINE pappend #-}
instance StatMonoid Mean Word64 where
  pappend = addValueToMean fromIntegral
  {-# INLINE pappend #-}


----------------------------------------------------------------
-- Generic monoids
----------------------------------------------------------------

-- | Monoid which allows to calculate two statistics in parralel
data TwoStats a b = TwoStats { calcStat1 :: a
                             , calcStat2 :: b
                             }

instance (Monoid a, Monoid b) => Monoid (TwoStats a b) where
  mempty = TwoStats mempty mempty
  mappend !(TwoStats x y) !(TwoStats x' y') = 
    TwoStats (mappend x x') (mappend y y')
  {-# INLINE mempty  #-}
  {-# INLINE mappend #-}

instance (StatMonoid a x, StatMonoid b x) => StatMonoid (TwoStats a b) x where
  pappend !x !(TwoStats a b) = TwoStats (pappend x a) (pappend x b)
  {-# INLINE pappend #-}


-- | Intermediate quantities to calculate the standard deviation.
-- Only samples of 'Double' are supported.
data Stdev = Stdev { sumOfSquares :: Double  -- ^ Current $\sum_i (x_i)^2$
                   , sumOfEntries :: Double  -- ^ Current $\sum_i x_i$
                   , sampleCountStdev :: Int -- ^ Length of the sample.
                   }
           deriving Show

-- | Calculate mean of the sample (use 'Mean' if you need only it).
mean :: Stdev -> Double
mean !(Stdev sumsq sumxs n) = sumxs / fromIntegral n

-- | Calculate standard deviation of the sample (unbiased estimator, $\sigma$).
stdev' :: Stdev -> Double
stdev' !(Stdev sumsq sumxs n) = sqrt $ (sumsq - sumxs ^ 2 / n') / n'
  where n' = fromIntegral n

-- | Calculate sample standard deviation (biased estimator, $s$).
stdev :: Stdev -> Double
stdev = sqrt . variance

-- | Calculate unbiased estimate of the variance.
variance :: Stdev -> Double
variance !(Stdev sumsq sumxs n) = (sumsq - sumxs^2 / n') / (n'-1)
  where n' = fromIntegral n

instance Monoid Stdev where
  mempty = Stdev 0 0 0
  mappend !(Stdev sumsq1 sum1 n1) !(Stdev sumsq2 sum2 n2) =
           Stdev (sumsq1 + sumsq2) (sum1 + sum2) (n1 + n2)
  {-# INLINE mempty #-}
  {-# INLINE mappend #-}

stdevOfOne :: Double -> Stdev
stdevOfOne !x = Stdev (x^2) x 1

instance StatMonoid Stdev Double where
  pappend !x !(Stdev sumsq sum' n) = Stdev (sumsq + x^2) (sum' + x) (n + 1)
            
-- $info
--
-- Statistic is function of a sample which does not depend on order of
-- elements in a sample. For each statistics corresponding monoid
-- could be constructed:
--
-- > f :: [A] -> B
-- >
-- > data F = F [A]
-- >
-- > evalF (F xs) = f xs
-- >
-- > instance Monoid F here
-- >   mempty = F []
-- >   (F a) `mappend` (F b) = F (a ++ b)
--
-- This indeed proves that monoid could be constructed. Monoid above
-- is completely impractical. It runs in O(n) space. However for some
-- statistics monoids which runs in O(1) space could be
-- implemented. For example mean. 
--
-- On the other hand some statistics could not be implemented in such
-- way. For example calculation of median require O(n) space. Variance
-- could be implemented in O(1) but such implementation won't be
-- numerically stable. 
