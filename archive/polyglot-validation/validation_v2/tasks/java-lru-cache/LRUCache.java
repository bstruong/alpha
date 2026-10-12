import java.util.*;

/**
 * LRU Cache — doubly-linked-list + hashmap implementation with -ea assertions.
 */
public class LRUCache {

    private final int capacity;
    private final Map<Integer, Node> map = new LinkedHashMap<>(16, 0.75f, true);

    /** Doubly-linked list node. */
    private static class Node {
        int key;
        int value;
        Node prev, next;
        Node(int key, int value) {
            this.key = key;
            this.value = value;
        }
    }

    public LRUCache(int capacity) {
        if (capacity <= 0) throw new IllegalArgumentException("capacity > 0");
        this.capacity = capacity;
    }

    public int get(int key) {
        if (!map.containsKey(key)) return -1;
        return map.get(key).value;
    }

    public void put(int key, int value) {
        if (map.containsKey(key)) {
            map.get(key).value = value;
            return;
        }
        if (map.size() >= capacity) {
            // Remove eldest entry (first in iteration order = LRU).
            Iterator<Integer> it = map.keySet().iterator();
            map.remove(it.next());
        }
        map.put(key, new Node(key, value));
    }

    public int size() {
        return map.size();
    }

    /** Check if key is present. */
    public boolean containsKey(int key) {
        return map.containsKey(key);
    }

    // --- Assertions ---
    public static void main(String[] args) {
        // 1. Basic put/get
        LRUCache cache = new LRUCache(3);
        cache.put(1, 10);
        cache.put(2, 20);
        cache.put(3, 30);
        assert cache.get(1) == 10 : "get(1) should be 10";
        assert cache.get(2) == 20 : "get(2) should be 20";
        assert cache.get(3) == 30 : "get(3) should be 30";

        // 2. Missing key returns -1
        assert cache.get(99) == -1 : "missing key should return -1";

        // 3. LRU eviction — accessing key 1 makes it MRU, so key 2 should be evicted
        cache.get(1); // move 1 to MRU
        cache.put(4, 40); // evicts 2 (LRU)
        assert !cache.containsKey(2) : "key 2 should be evicted";
        assert cache.get(1) == 10 : "key 1 should still exist";
        assert cache.get(4) == 40 : "key 4 should exist";
        assert cache.size() == 3 : "size should be 3";

        // 4. Update existing key
        cache.put(1, 100);
        assert cache.get(1) == 100 : "update key 1 to 100";

        // 5. Capacity=1
        LRUCache tiny = new LRUCache(1);
        tiny.put(1, 1);
        tiny.put(2, 2);
        assert !tiny.containsKey(1) : "key 1 evicted";
        assert tiny.get(2) == 2 : "key 2 exists";

        // 6. Invalid capacity
        try {
            new LRUCache(0);
            assert false : "should have thrown";
        } catch (IllegalArgumentException e) {
            // expected
        }

        System.out.println("java-lru-cache: all assertions passed.");
    }
}
