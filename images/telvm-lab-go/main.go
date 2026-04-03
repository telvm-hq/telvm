package main

import (
	"github.com/gofiber/fiber/v2"
)

func main() {
	app := fiber.New()
	app.Get("/", func(c *fiber.Ctx) error {
		return c.JSON(fiber.Map{
			"status":  "ok",
			"service": "telvm-lab",
			"probe":   "/",
		})
	})
	if err := app.Listen(":3333"); err != nil {
		panic(err)
	}
}
