import java.util.*;

/** Simple LRU Cache using LinkedHashMap. */
public class LRUCache {
    private final int capacity;
    private final LinkedHashMap<Integer, Integer> map;

    public LRUCache(int capacity) {
        this.capacity = capacity;
        this.map = new LinkedHashMap<>(capacity, 0.75f, true) {
            @Override
            protected boolean removeEldestEntry(Map.Entry<Integer, Integer> eldest) {
                return size() > capacity;
            }
        };
    }

    public Integer get(int key) {
        return map.get(key);
    }

    public void put(int key, int value) {
        map.put(key, value);
    }

    public int size() {
        return map.size();
    }

    public static void main(String[] args) {
        LRUCache cache = new LRUCache(2);
        cache.put(1, 1);
        cache.put(2, 2);
        assert cache.get(1) == 1 : "get(1) should be 1";
        cache.put(3, 3); // evicts key 2
        assert cache.get(2) == null : "get(2) should be null (evicted)";
        cache.put(4, 4); // evicts key 1
        assert cache.get(1) == null : "get(1) should be null (evicted)";
        assert cache.get(3) == 3 : "get(3) should be 3";
        assert cache.get(4) == 4 : "get(4) should be 4";
        System.out.println("All assertions passed.");
    }
}
