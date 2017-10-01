{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE BangPatterns          #-}
{-# LANGUAGE DeriveDataTypeable    #-}
{-# LANGUAGE DeriveGeneric         #-}
{-# LANGUAGE FlexibleContexts      #-}
{-# LANGUAGE FlexibleInstances     #-}
{-# LANGUAGE MultiParamTypeClasses #-}
module Data.Monoid.Statistics.Numeric ( 
    -- * Mean and variance
    CountG(..)
  , Count
  , asCount
  , Mean(..)
  , asMean
  , Variance(..)
  , asVariance
    -- ** Ad-hoc accessors
    -- $accessors
  , CalcCount(..)
  , CalcMean(..)
  , CalcVariance(..)
  , calcStddev
  , calcStddevUnbiased
    -- * Maximum and minimum
  , Max(..)
  , Min(..)
  ) where

import Data.Monoid
import Data.Monoid.Statistics.Class
import Data.Data (Typeable,Data)
import GHC.Generics (Generic)

----------------------------------------------------------------
-- Statistical monoids
----------------------------------------------------------------

-- | Simplest statistics. Number of elements in the sample
newtype CountG a = CountG { calcCountN :: a }
                  deriving (Show,Eq,Ord,Typeable)

type Count = CountG Int

-- | Fix type of monoid
asCount :: CountG a -> CountG a
asCount = id

instance Integral a => Monoid (CountG a) where
  mempty                      = CountG 0
  CountG i `mappend` CountG j = CountG (i + j)
  {-# INLINE mempty  #-}
  {-# INLINE mappend #-}
  
instance (Integral a) => StatMonoid (CountG a) b where
  singletonMonoid _            = CountG 1
  addValue        (CountG n) _ = CountG (n + 1)
  {-# INLINE singletonMonoid #-}
  {-# INLINE addValue        #-}

instance CalcCount (CountG Int) where
  calcCount = calcCountN
  {-# INLINE calcCount #-}



----------------------------------------------------------------

-- | Mean of sample. Samples of Double,Float and bui;t-in integral
--   types are supported
--
-- Numeric stability of 'mappend' is not proven.
data Mean = Mean !Int    -- Number of entries
                 !Double -- Current mean
            deriving (Show,Eq,Typeable,Data,Generic)

-- | Fix type of monoid
asMean :: Mean -> Mean
asMean = id

instance Monoid Mean where
  mempty = Mean 0 0
  mappend (Mean n x) (Mean k y) = Mean (n + k) ((x*n' + y*k') / (n' + k')) 
    where
      n' = fromIntegral n
      k' = fromIntegral k
  {-# INLINE mempty  #-}
  {-# INLINE mappend #-}

instance Real a => StatMonoid Mean a where
  addValue (Mean n m) !x = Mean n' (m + (realToFrac x - m) / fromIntegral n') where n' = n+1
  {-# INLINE addValue #-}

instance CalcCount Mean where
  calcCount (Mean n _) = n
instance CalcMean Mean where
  calcMean (Mean _ m) = m



----------------------------------------------------------------

-- | Intermediate quantities to calculate the standard deviation.
data Variance = Variance {-# UNPACK #-} !Int    --  Number of elements in the sample
                         {-# UNPACK #-} !Double -- Current sum of elements of sample
                         {-# UNPACK #-} !Double -- Current sum of squares of deviations from current mean
                deriving (Show,Eq,Typeable)

-- | Fix type of monoid
asVariance :: Variance -> Variance
asVariance = id
{-# INLINE asVariance #-}

-- | Using parallel algorithm from:
-- 
-- Chan, Tony F.; Golub, Gene H.; LeVeque, Randall J. (1979),
-- Updating Formulae and a Pairwise Algorithm for Computing Sample
-- Variances., Technical Report STAN-CS-79-773, Department of
-- Computer Science, Stanford University. Page 4.
-- 
-- <ftp://reports.stanford.edu/pub/cstr/reports/cs/tr/79/773/CS-TR-79-773.pdf>
--
instance Monoid Variance where
  mempty = Variance 0 0 0
  mappend (Variance n1 ta sa) (Variance n2 tb sb) = Variance (n1+n2) (ta+tb) sumsq
    where
      na = fromIntegral n1
      nb = fromIntegral n2
      nom = sqr (ta * nb - tb * na)
      sumsq
        | n1 == 0 || n2 == 0 = sa + sb  -- because either sa or sb should be 0
        | otherwise          = sa + sb + nom / ((na + nb) * na * nb)
  {-# INLINE mempty #-}
  {-# INLINE mappend #-}

instance Real a => StatMonoid Variance a where
  -- Can be implemented directly as in Welford-Knuth algorithm.
  addValue !s !x = s `mappend` (Variance 1 (realToFrac x) 0)
  {-# INLINE addValue #-}

instance CalcCount Variance where
  calcCount (Variance n _ _) = n
instance CalcMean Variance where
  calcMean (Variance n t _) = t / fromIntegral n
  {-# INLINE calcMean #-}
instance CalcVariance Variance where
  calcVariance (Variance n _ s) = s / fromIntegral n
  calcVarianceUnbiased (Variance n _ s) = s / fromIntegral (n-1)



----------------------------------------------------------------

newtype Min a = Min { calcMin :: Maybe a }

instance Ord a => Monoid (Min a) where
  mempty = Min Nothing
  Min (Just a) `mappend` Min (Just b) = Min (Just $! min a b)
  Min a        `mappend` Min Nothing  = Min a
  Min Nothing  `mappend` Min b        = Min b

instance (Ord a, a ~ a') => StatMonoid (Min a) a' where
  singletonMonoid a = Min (Just a)

----------------------------------------------------------------

newtype Max a = Max { calcMax :: Maybe a }

instance Ord a => Monoid (Max a) where
  mempty = Max Nothing
  Max (Just a) `mappend` Max (Just b) = Max (Just $! min a b)
  Max a        `mappend` Max Nothing  = Max a
  Max Nothing  `mappend` Max b        = Max b

instance (Ord a, a ~ a') => StatMonoid (Max a) a' where
  singletonMonoid a = Max (Just a)


----------------------------------------------------------------

-- | Calculate minimum of sample. For empty sample returns NaN. Any
-- NaN encountered will be ignored. 
newtype MinD = MinD { calcMinD :: Double }
              deriving (Show,Eq,Ord,Typeable,Data,Generic)

-- N.B. forall (x :: Double) (x <= NaN) == False
instance Monoid MinD where
  mempty = MinD (0/0)
  mappend (MinD x) (MinD y) 
    | isNaN x   = MinD y
    | isNaN y   = MinD x
    | otherwise = MinD (min x y)
  {-# INLINE mempty  #-}
  {-# INLINE mappend #-}  

instance a ~ Double => StatMonoid MinD a where
  singletonMonoid = MinD

-- | Calculate maximum of sample. For empty sample returns NaN. Any
-- NaN encountered will be ignored. 
newtype MaxD = MaxD { calcMaxD :: Double }
              deriving (Show,Eq,Ord,Typeable,Data,Generic)

instance Monoid MaxD where
  mempty = MaxD (0/0)
  mappend (MaxD x) (MaxD y) 
    | isNaN x   = MaxD y
    | isNaN y   = MaxD x
    | otherwise = MaxD (max x y)
  {-# INLINE mempty  #-}
  {-# INLINE mappend #-}  

instance a ~ Double => StatMonoid MaxD a where
  singletonMonoid = MaxD





----------------------------------------------------------------
-- Ad-hoc type class
----------------------------------------------------------------
  
-- $accessors
--
-- Monoids 'Count', 'Mean' and 'Variance' form some kind of tower.
-- Every successive monoid can calculate every statistics previous
-- monoids can. So to avoid replicating accessors for each statistics
-- a set of ad-hoc type classes was added. 
--
-- This approach have deficiency. It becomes to infer type of monoidal
-- accumulator from accessor function so following expression will be
-- rejected:
-- 
-- > calcCount $ evalStatistics xs
--
-- Indeed type of accumulator is:
--
-- > forall a . (StatMonoid a, CalcMean a) => a
--
-- Therefore it must be fixed by adding explicit type annotation. For
-- example:
--
-- > calcMean (evalStatistics xs :: Mean)

  

-- | Statistics which could count number of elements in the sample
class CalcCount m where
  -- | Number of elements in sample
  calcCount :: m -> Int

-- | Statistics which could estimate mean of sample
class CalcMean m where
  -- | Calculate esimate of mean of a sample
  calcMean :: m -> Double
  
-- | Statistics which could estimate variance of sample
class CalcVariance m where
  -- | Calculate biased estimate of variance
  calcVariance         :: m -> Double
  -- | Calculate unbiased estimate of the variance, where the
  --   denominator is $n-1$.
  calcVarianceUnbiased :: m -> Double

-- | Calculate sample standard deviation (biased estimator, $s$, where
--   the denominator is $n-1$).
calcStddev :: CalcVariance m => m -> Double
calcStddev = sqrt . calcVariance
{-# INLINE calcStddev #-}

-- | Calculate standard deviation of the sample
-- (unbiased estimator, $\sigma$, where the denominator is $n$).
calcStddevUnbiased :: CalcVariance m => m -> Double
calcStddevUnbiased = sqrt . calcVarianceUnbiased
{-# INLINE calcStddevUnbiased #-}



----------------------------------------------------------------
-- Helpers
----------------------------------------------------------------
 
sqr :: Double -> Double
sqr x = x * x
{-# INLINE sqr #-}
