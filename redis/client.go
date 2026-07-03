package redis

import (
	"context"
	"fmt"
	"log"

	goredis "github.com/redis/go-redis/v9"
)

var Client *goredis.Client

func Connect(redisURL string) {
	opt, err := goredis.ParseURL(redisURL)
	if err != nil {
		log.Fatalf("Invalid Redis URL: %v", err)
	}
	Client = goredis.NewClient(opt)
	_, err = Client.Ping(context.Background()).Result()
	if err != nil {
		log.Fatalf("Redis connection failed: %v", err)
	}
	fmt.Println("Connected to Redis")
}

func Close() {
	Client.Close()
}

func IsBlacklisted(token string) bool {
	val, err := Client.Get(context.Background(), "blacklist:"+token).Result()
	if err != nil || val == "" {
		return false
	}
	return true
}
