{-# LANGUAGE CPP #-}
{-# LANGUAGE DeriveDataTypeable #-}
{-# LANGUAGE DeriveFunctor #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE TemplateHaskellQuotes #-}
{-# LANGUAGE PatternSynonyms #-}

-- |
-- An abstract interface for maps from JSON keys to values.

module Data.Aeson.KeyMap (
    -- * Map Type
    KeyMap,

    -- * Query
    null,
    lookup,
    size,
    member,

    -- * Construction
    empty,
    singleton,

    -- ** Insertion
    insert,

    -- * Deletion
    delete,

    -- * Update
    alterF,

    -- * Combine
    difference,
    union,
    unionWith,
    unionWithKey,
    intersection,
    intersectionWith,
    intersectionWithKey,
    alignWith,
    alignWithKey,

    -- * Lists
    fromList,
    fromListWith,
    toList,
    toAscList,

    -- * Maps
    fromHashMap,
    toHashMap,
    coercionToHashMap,
    fromMap,
    toMap,
    coercionToMap,
    fromHashMapText,
    toHashMapText,

    -- * Traversal
    -- ** Map
    map,
    mapKeyVal,
    traverse,
    traverseWithKey,

    -- * Folds
    foldr,
    foldr',
    foldl,
    foldl',
    foldMapWithKey,
    foldrWithKey,

    -- * Conversions
    keys,

    -- * Filter
    filter,
    filterWithKey,
    mapMaybe,
    mapMaybeWithKey,
) where

-- Import stuff from Prelude explicitly
import Prelude (Eq(..), Ord((>)), Int, Bool(..), Maybe(..), id)
import Prelude ((.), ($))
import Prelude (Functor(fmap), Monad(..))
import Prelude (Show, showsPrec, showParen, shows, showString)

import Control.Applicative (Applicative)
import Control.DeepSeq (NFData(..))
import Data.Aeson.Key (Key)
import Data.Bifunctor (first)
import Data.Data (Data)
import Data.Hashable (Hashable(..))
import Data.HashMap.Strict (HashMap)
import Data.Map (Map)
import Data.Monoid (Monoid(mempty, mappend))
import Data.Semigroup (Semigroup((<>)))
import Data.Text (Text)
import Data.These (These (..))
import Data.Type.Coercion (Coercion (..))
import Data.Typeable (Typeable)
import Text.Read (Read (..), Lexeme(..), readListPrecDefault, prec, lexP, parens)

import qualified Data.Aeson.Key as Key
import qualified Data.Foldable as F
import qualified Data.Traversable as T
import qualified Data.HashMap.Strict as H
import qualified Data.List as L
import qualified Data.Map.Strict as M
import qualified Language.Haskell.TH.Syntax as TH
import qualified Data.Foldable.WithIndex    as WI (FoldableWithIndex (..))
import qualified Data.Functor.WithIndex     as WI (FunctorWithIndex (..))
import qualified Data.Traversable.WithIndex as WI (TraversableWithIndex (..))
import qualified Data.Semialign as SA
import qualified Data.Semialign.Indexed as SAI
import qualified Witherable as W

#ifdef USE_ORDEREDMAP

-------------------------------------------------------------------------------
-- Map
-------------------------------------------------------------------------------

-- | A map from JSON key type 'Key' to 'v'.
type KeyMap v = HashMap Key v

pattern KeyMap a = a where
  KeyMap a <- a

-- | Construct an empty map.
empty :: KeyMap v
empty = KeyMap H.empty

-- | Is the map empty?
null :: KeyMap v -> Bool
null = H.null . unKeyMap

-- | Return the number of key-value mappings in this map.
size :: KeyMap v -> Int
size = H.size . unKeyMap

-- | Construct a map with a single element.
singleton :: Key -> v -> KeyMap v
singleton k v = KeyMap (H.singleton k v)

-- | Is the key a member of the map?
member :: Key -> KeyMap a -> Bool
member t (KeyMap m) = H.member t m

-- | Remove the mapping for the specified key from this map if present.
delete :: Key -> KeyMap v -> KeyMap v
delete k (KeyMap m) = KeyMap (H.delete k m)

-- | 'alterF' can be used to insert, delete, or update a value in a map.
alterF :: Functor f => (Maybe v -> f (Maybe v)) -> Key -> KeyMap v -> f (KeyMap v)
#if MIN_VERSION_containers(0,5,8)
alterF f k = fmap KeyMap . H.alterF f k . unKeyMap
#else
alterF f k m = fmap g (f mv) where
    g r =  case r of
        Nothing -> case mv of
            Nothing -> m
            Just _  -> delete k m
        Just v' -> insert k v' m

    mv = lookup k m
#endif

-- | Return the value to which the specified key is mapped,
-- or Nothing if this map contains no mapping for the key.
lookup :: Key -> KeyMap v -> Maybe v
lookup t tm = H.lookup t (unKeyMap tm)

-- | Associate the specified value with the specified key
-- in this map. If this map previously contained a mapping
-- for the key, the old value is replaced.
insert :: Key -> v -> KeyMap v -> KeyMap v
insert k v tm = KeyMap (H.insert k v (unKeyMap tm))

-- | Map a function over all values in the map.
map :: (a -> b) -> KeyMap a -> KeyMap b
map = fmap

-- | Map a function over all values in the map.
mapWithKey :: (Key -> a -> b) -> KeyMap a -> KeyMap b
mapWithKey f (KeyMap m) = KeyMap (H.mapWithKey f m)

foldMapWithKey :: Monoid m => (Key -> a -> m) -> KeyMap a -> m
foldMapWithKey f (KeyMap m) = H.foldMapWithKey f m

foldr :: (a -> b -> b) -> b -> KeyMap a -> b
foldr f z (KeyMap m) = H.foldr f z m

foldr' :: (a -> b -> b) -> b -> KeyMap a -> b
foldr' f z (KeyMap m) = H.foldr' f z m

foldl :: (b -> a -> b) -> b -> KeyMap a -> b
foldl f z (KeyMap m) = H.foldl f z m

foldl' :: (b -> a -> b) -> b -> KeyMap a -> b
foldl' f z (KeyMap m) = H.foldl' f z m

-- | Reduce this map by applying a binary operator to all
-- elements, using the given starting value (typically the
-- right-identity of the operator).
foldrWithKey :: (Key -> v -> a -> a) -> a -> KeyMap v -> a
foldrWithKey f a = H.foldrWithKey f a . unKeyMap

-- | Perform an Applicative action for each key-value pair
-- in a 'KeyMap' and produce a 'KeyMap' of all the results.
traverse :: Applicative f => (v1 -> f v2) -> KeyMap v1 -> f (KeyMap v2)
traverse f = fmap KeyMap . T.traverse f . unKeyMap

-- | Perform an Applicative action for each key-value pair
-- in a 'KeyMap' and produce a 'KeyMap' of all the results.
traverseWithKey :: Applicative f => (Key -> v1 -> f v2) -> KeyMap v1 -> f (KeyMap v2)
traverseWithKey f = fmap KeyMap . H.traverseWithKey f  . unKeyMap

-- | Construct a map from a list of elements. Uses the
-- provided function, f, to merge duplicate entries with
-- (f newVal oldVal).
fromListWith :: (v -> v -> v) ->  [(Key, v)] -> KeyMap v
fromListWith op = KeyMap . H.fromListWith op

-- |  Construct a map with the supplied mappings. If the
-- list contains duplicate mappings, the later mappings take
-- precedence.
fromList :: [(Key, v)] -> KeyMap v
fromList = KeyMap . H.fromList

-- | Return a list of this map's elements.
--
-- The order is not stable. Use 'toAscList' for stable ordering.
toList :: KeyMap v -> [(Key, v)]
toList = H.toList . unKeyMap

-- | Return a list of this map's elements in ascending order
-- based of the textual key.
toAscList :: KeyMap v -> [(Key, v)]
toAscList = H.toAscList . unKeyMap

-- | Difference of two maps. Return elements of the first
-- map not existing in the second.
difference :: KeyMap v -> KeyMap v' -> KeyMap v
difference tm1 tm2 = KeyMap (H.difference (unKeyMap tm1) (unKeyMap tm2))

-- The (left-biased) union of two maps. It prefers the first map when duplicate
-- keys are encountered, i.e. ('union' == 'unionWith' 'const').
union :: KeyMap v -> KeyMap v -> KeyMap v
union (KeyMap x) (KeyMap y) = KeyMap (H.union x y)

-- | The union with a combining function.
unionWith :: (v -> v -> v) -> KeyMap v -> KeyMap v -> KeyMap v
unionWith f (KeyMap x) (KeyMap y) = KeyMap (H.unionWith f x y)

-- | The union with a combining function.
unionWithKey :: (Key -> v -> v -> v) -> KeyMap v -> KeyMap v -> KeyMap v
unionWithKey f (KeyMap x) (KeyMap y) = KeyMap (H.unionWithKey f x y)

-- | The (left-biased) intersection of two maps (based on keys).
intersection :: KeyMap a -> KeyMap b -> KeyMap a
intersection (KeyMap x) (KeyMap y) = KeyMap (H.intersection x y)

-- | The intersection with a combining function.
intersectionWith :: (a -> b -> c) -> KeyMap a -> KeyMap b -> KeyMap c
intersectionWith f (KeyMap x) (KeyMap y) = KeyMap (H.intersectionWith f x y)

-- | The intersection with a combining function.
intersectionWithKey :: (Key -> a -> b -> c) -> KeyMap a -> KeyMap b -> KeyMap c
intersectionWithKey f (KeyMap x) (KeyMap y) = KeyMap (H.intersectionWithKey f x y)

-- | Return a list of this map's keys.
keys :: KeyMap v -> [Key]
keys = H.keys . unKeyMap

-- | Convert a 'KeyMap' to a 'HashMap'.
toHashMap :: KeyMap v -> HashMap Key v
toHashMap = H.fromList . toList

-- | Convert a 'HashMap' to a 'KeyMap'.
fromHashMap :: HashMap Key v -> KeyMap v
fromHashMap = fromList . H.toList

-- | Convert a 'KeyMap' to a 'Map'.
toMap :: KeyMap v -> Map Key v
toMap = unKeyMap

-- | Convert a 'HashMap' to a 'Map'.
fromMap :: Map Key v -> KeyMap v
fromMap = KeyMap

coercionToHashMap :: Maybe (Coercion (HashMap Key v) (KeyMap v))
coercionToHashMap = Nothing
{-# INLINE coercionToHashMap #-}

coercionToMap :: Maybe (Coercion (Map Key v) (KeyMap v))
coercionToMap = Just Coercion
{-# INLINE coercionToMap #-}

-- | Transform the keys and values of a 'KeyMap'.
mapKeyVal :: (Key -> Key) -> (v1 -> v2)
          -> KeyMap v1 -> KeyMap v2
mapKeyVal fk kv = foldrWithKey (\k v -> insert (fk k) (kv v)) empty
{-# INLINE mapKeyVal #-}

-- | Filter all keys/values that satisfy some predicate.
filter :: (v -> Bool) -> KeyMap v -> KeyMap v
filter f (KeyMap m) = KeyMap (H.filter f m)

-- | Filter all keys/values that satisfy some predicate.
filterWithKey :: (Key -> v -> Bool) -> KeyMap v -> KeyMap v
filterWithKey f (KeyMap m) = KeyMap (H.filterWithKey f m)

-- | Map values and collect the Just results.
mapMaybe :: (a -> Maybe b) -> KeyMap a -> KeyMap b
mapMaybe f (KeyMap m) = KeyMap (H.mapMaybe f m)

-- | Map values and collect the Just results.
mapMaybeWithKey :: (Key -> v -> Maybe u) -> KeyMap v -> KeyMap u
mapMaybeWithKey f (KeyMap m) = KeyMap (H.mapMaybeWithKey f m)

#else

-------------------------------------------------------------------------------
-- HashMap
-------------------------------------------------------------------------------

import Data.List (sortBy)
import Data.Ord (comparing)
import Prelude (fst)

-- | A map from JSON key type 'Key' to 'v'.
type KeyMap v = HashMap Key v

pattern KeyMap :: HashMap Key v -> KeyMap v
pattern KeyMap a <- a where
  KeyMap a = a

unKeyMap :: KeyMap v -> HashMap Key v
unKeyMap = id

-- | Construct an empty map.
empty :: KeyMap v
empty = KeyMap H.empty

-- | Is the map empty?
null :: KeyMap v -> Bool
null = H.null . unKeyMap

-- | Return the number of key-value mappings in this map.
size :: KeyMap v -> Int
size = H.size . unKeyMap

-- | Construct a map with a single element.
singleton :: Key -> v -> KeyMap v
singleton k v = KeyMap (H.singleton k v)

-- | Is the key a member of the map?
member :: Key -> KeyMap a -> Bool
member t (KeyMap m) = H.member t m

-- | Remove the mapping for the specified key from this map if present.
delete :: Key -> KeyMap v -> KeyMap v
delete k (KeyMap m) = KeyMap (H.delete k m)

-- | 'alterF' can be used to insert, delete, or update a value in a map.
alterF :: Functor f => (Maybe v -> f (Maybe v)) -> Key -> KeyMap v -> f (KeyMap v)
alterF f k = fmap KeyMap . H.alterF f k . unKeyMap

-- | Return the value to which the specified key is mapped,
-- or Nothing if this map contains no mapping for the key.
lookup :: Key -> KeyMap v -> Maybe v
lookup t tm = H.lookup t (unKeyMap tm)

-- | Associate the specified value with the specified key
-- in this map. If this map previously contained a mapping
-- for the key, the old value is replaced.
insert :: Key -> v -> KeyMap v -> KeyMap v
insert k v tm = KeyMap (H.insert k v (unKeyMap tm))

-- | Map a function over all values in the map.
map :: (a -> b) -> KeyMap a -> KeyMap b
map = fmap

-- | Map a function over all values in the map.
mapWithKey :: (Key -> a -> b) -> KeyMap a -> KeyMap b
mapWithKey f (KeyMap m) = KeyMap (H.mapWithKey f m)

foldMapWithKey :: Monoid m => (Key -> a -> m) -> KeyMap a -> m
foldMapWithKey f (KeyMap m) = H.foldMapWithKey f m

foldr :: (a -> b -> b) -> b -> KeyMap a -> b
foldr f z (KeyMap m) = H.foldr f z m

foldr' :: (a -> b -> b) -> b -> KeyMap a -> b
foldr' f z (KeyMap m) = H.foldr' f z m

foldl :: (b -> a -> b) -> b -> KeyMap a -> b
foldl f z (KeyMap m) = H.foldl f z m

foldl' :: (b -> a -> b) -> b -> KeyMap a -> b
foldl' f z (KeyMap m) = H.foldl' f z m

-- | Reduce this map by applying a binary operator to all
-- elements, using the given starting value (typically the
-- right-identity of the operator).
foldrWithKey :: (Key -> v -> a -> a) -> a -> KeyMap v -> a
foldrWithKey f a = H.foldrWithKey f a . unKeyMap

-- | Perform an Applicative action for each key-value pair
-- in a 'KeyMap' and produce a 'KeyMap' of all the results.
traverse :: Applicative f => (v1 -> f v2) -> KeyMap v1 -> f (KeyMap v2)
traverse f = fmap KeyMap . T.traverse f . unKeyMap

-- | Perform an Applicative action for each key-value pair
-- in a 'KeyMap' and produce a 'KeyMap' of all the results.
traverseWithKey :: Applicative f => (Key -> v1 -> f v2) -> KeyMap v1 -> f (KeyMap v2)
traverseWithKey f = fmap KeyMap . H.traverseWithKey f  . unKeyMap

-- | Construct a map from a list of elements. Uses the
-- provided function, f, to merge duplicate entries with
-- (f newVal oldVal).
fromListWith :: (v -> v -> v) ->  [(Key, v)] -> KeyMap v
fromListWith op = KeyMap . H.fromListWith op

-- |  Construct a map with the supplied mappings. If the
-- list contains duplicate mappings, the later mappings take
-- precedence.
fromList :: [(Key, v)] -> KeyMap v
fromList = KeyMap . H.fromList

-- | Return a list of this map's elements.
--
-- The order is not stable. Use 'toAscList' for stable ordering.
toList :: KeyMap v -> [(Key, v)]
toList = H.toList . unKeyMap

-- | Return a list of this map's elements in ascending order
-- based of the textual key.
toAscList :: KeyMap v -> [(Key, v)]
toAscList = sortBy (comparing fst) . toList

-- | Difference of two maps. Return elements of the first
-- map not existing in the second.
difference :: KeyMap v -> KeyMap v' -> KeyMap v
difference tm1 tm2 = KeyMap (H.difference (unKeyMap tm1) (unKeyMap tm2))

-- The (left-biased) union of two maps. It prefers the first map when duplicate
-- keys are encountered, i.e. ('union' == 'unionWith' 'const').
union :: KeyMap v -> KeyMap v -> KeyMap v
union (KeyMap x) (KeyMap y) = KeyMap (H.union x y)

-- | The union with a combining function.
unionWith :: (v -> v -> v) -> KeyMap v -> KeyMap v -> KeyMap v
unionWith f (KeyMap x) (KeyMap y) = KeyMap (H.unionWith f x y)

-- | The union with a combining function.
unionWithKey :: (Key -> v -> v -> v) -> KeyMap v -> KeyMap v -> KeyMap v
unionWithKey f (KeyMap x) (KeyMap y) = KeyMap (H.unionWithKey f x y)

-- | The (left-biased) intersection of two maps (based on keys).
intersection :: KeyMap a -> KeyMap b -> KeyMap a
intersection (KeyMap x) (KeyMap y) = KeyMap (H.intersection x y)

-- | The intersection with a combining function.
intersectionWith :: (a -> b -> c) -> KeyMap a -> KeyMap b -> KeyMap c
intersectionWith f (KeyMap x) (KeyMap y) = KeyMap (H.intersectionWith f x y)

-- | The intersection with a combining function.
intersectionWithKey :: (Key -> a -> b -> c) -> KeyMap a -> KeyMap b -> KeyMap c
intersectionWithKey f (KeyMap x) (KeyMap y) = KeyMap (H.intersectionWithKey f x y)

-- | Return a list of this map's keys.
keys :: KeyMap v -> [Key]
keys = H.keys . unKeyMap

-- | Convert a 'KeyMap' to a 'HashMap'.
toHashMap :: KeyMap v -> HashMap Key v
toHashMap = unKeyMap

-- | Convert a 'HashMap' to a 'KeyMap'.
fromHashMap :: HashMap Key v -> KeyMap v
fromHashMap = KeyMap

-- | Convert a 'KeyMap' to a 'Map'.
toMap :: KeyMap v -> Map Key v
toMap = M.fromList . toList

-- | Convert a 'HashMap' to a 'Map'.
fromMap :: Map Key v -> KeyMap v
fromMap = fromList . M.toList

coercionToHashMap :: Maybe (Coercion (HashMap Key v) (KeyMap v))
coercionToHashMap = Just Coercion
{-# INLINE coercionToHashMap #-}

coercionToMap :: Maybe (Coercion (Map Key v) (KeyMap v))
coercionToMap = Nothing
{-# INLINE coercionToMap #-}

-- | Transform the keys and values of a 'KeyMap'.
mapKeyVal :: (Key -> Key) -> (v1 -> v2)
          -> KeyMap v1 -> KeyMap v2
mapKeyVal fk kv = foldrWithKey (\k v -> insert (fk k) (kv v)) empty
{-# INLINE mapKeyVal #-}

-- | Filter all keys/values that satisfy some predicate.
filter :: (v -> Bool) -> KeyMap v -> KeyMap v
filter f (KeyMap m) = KeyMap (H.filter f m)

-- | Filter all keys/values that satisfy some predicate.
filterWithKey :: (Key -> v -> Bool) -> KeyMap v -> KeyMap v
filterWithKey f (KeyMap m) = KeyMap (H.filterWithKey f m)

-- | Map values and collect the Just results.
mapMaybe :: (a -> Maybe b) -> KeyMap a -> KeyMap b
mapMaybe f (KeyMap m) = KeyMap (H.mapMaybe f m)

-- | Map values and collect the Just results.
mapMaybeWithKey :: (Key -> v -> Maybe u) -> KeyMap v -> KeyMap u
mapMaybeWithKey f (KeyMap m) = KeyMap (H.mapMaybeWithKey f m)

#endif

-------------------------------------------------------------------------------
-- combinators using existing abstractions
-------------------------------------------------------------------------------

-- | Generalized union with combining function.
alignWith :: (These a b -> c) -> KeyMap a -> KeyMap b -> KeyMap c
alignWith f (KeyMap x) (KeyMap y) = KeyMap (SA.alignWith f x y)

-- | Generalized union with combining function.
alignWithKey :: (Key -> These a b -> c) -> KeyMap a -> KeyMap b -> KeyMap c
alignWithKey f (KeyMap x) (KeyMap y) = KeyMap (SAI.ialignWith f x y)

-- | Convert a 'KeyMap' to a @'HashMap' 'Text'@.
toHashMapText :: KeyMap v -> HashMap Text  v
toHashMapText = H.fromList . L.map (first Key.toText) . toList

-- | Convert a @'HashMap' 'Text'@to a 'KeyMap'.
fromHashMapText :: HashMap Text v -> KeyMap v
fromHashMapText = fromList . L.map (first Key.fromText) . H.toList

-------------------------------------------------------------------------------
-- Instances
-------------------------------------------------------------------------------

-- No instances for synonym
