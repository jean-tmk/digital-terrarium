package main

import (
	"context"
	"crypto/sha256"
	"encoding/json"
	"errors"
	"fmt"
	"math"
	"os"
	"strconv"
	"strings"
	"time"
)

type Habitat struct {
	ID           string             `json:"id"`
	Cycle        int                `json:"cycle"`
	Seed         int64              `json:"seed"`
	Moisture     float64            `json:"moisture"`
	Light        float64            `json:"light"`
	Temperature  float64            `json:"temperature"`
	Biodiversity float64            `json:"biodiversity"`
	Plants       map[string]float64 `json:"plants"`
	Visitors     map[string]float64 `json:"visitors"`
	UpdatedAt    string             `json:"updated_at"`
}

type Request struct {
	RawPath        string            `json:"rawPath"`
	RequestContext RequestContext    `json:"requestContext"`
	PathParameters map[string]string `json:"pathParameters"`
	Body           string            `json:"body"`
}

type RequestContext struct {
	HTTP HTTPContext `json:"http"`
}

type HTTPContext struct {
	Method string `json:"method"`
	Path   string `json:"path"`
}

type Response struct {
	StatusCode int               `json:"statusCode"`
	Headers    map[string]string `json:"headers"`
	Body       string            `json:"body"`
}

func clamp(value, minimum, maximum float64) float64 {
	return math.Max(minimum, math.Min(maximum, value))
}

func noise(seed int64, cycle int, channel string) float64 {
	sum := sha256.Sum256([]byte(fmt.Sprintf("%d:%d:%s", seed, cycle, channel)))
	n := int64(sum[0])<<8 | int64(sum[1])
	return float64(n)/65535.0*2.0 - 1.0
}

func defaultHabitat(id string, seed int64) Habitat {
	return Habitat{
		ID:           id,
		Cycle:        0,
		Seed:         seed,
		Moisture:     0.62,
		Light:        0.58,
		Temperature:  21.0,
		Biodiversity: 0.72,
		Plants: map[string]float64{
			"moon-moss":       0.8,
			"glass-fern":      0.65,
			"whisper-caps":    0.42,
			"button-vine":     0.55,
		},
		Visitors: map[string]float64{
			"pixel-moth": 0.32,
			"dew-snail":  0.18,
		},
		UpdatedAt: time.Now().UTC().Format(time.RFC3339),
	}
}

func advance(h Habitat) Habitat {
	h.Cycle++
	rain := noise(h.Seed, h.Cycle, "rain")
	sun := noise(h.Seed, h.Cycle, "sun")
	heat := noise(h.Seed, h.Cycle, "heat")

	h.Moisture = clamp(h.Moisture+rain*0.08-sun*0.035, 0.05, 1)
	h.Light = clamp(h.Light+sun*0.07, 0.08, 1)
	h.Temperature = clamp(h.Temperature+heat*1.4+sun*0.4, 8, 36)

	for species, population := range h.Plants {
		preferredMoisture := 0.55 + noise(h.Seed, 1, species)*0.16
		moistureFitness := 1 - math.Abs(h.Moisture-preferredMoisture)
		lightFitness := 1 - math.Abs(h.Light-0.58)
		growth := (moistureFitness*0.045 + lightFitness*0.025) - 0.038
		h.Plants[species] = clamp(population+growth, 0, 1)
	}

	plantMass := 0.0
	for _, population := range h.Plants {
		plantMass += population
	}
	plantMass /= float64(len(h.Plants))

	for species, population := range h.Visitors {
		change := (plantMass-0.45)*0.035 + noise(h.Seed, h.Cycle, species)*0.012
		h.Visitors[species] = clamp(population+change, 0, 1)
	}

	active := 0
	for _, population := range h.Plants {
		if population > 0.08 {
			active++
		}
	}
	h.Biodiversity = clamp(float64(active)/float64(len(h.Plants))*0.7+plantMass*0.3, 0, 1)
	h.UpdatedAt = time.Now().UTC().Format(time.RFC3339)
	return h
}

func jsonResponse(status int, payload any) Response {
	body, _ := json.Marshal(payload)
	return Response{
		StatusCode: status,
		Headers: map[string]string{
			"content-type":                 "application/json",
			"cache-control":                "no-store",
			"access-control-allow-origin":  "*",
		},
		Body: string(body),
	}
}

func route(ctx context.Context, request Request) (Response, error) {
	method := strings.ToUpper(request.RequestContext.HTTP.Method)
	id := request.PathParameters["id"]

	if method == "GET" && request.RawPath == "/health" {
		return jsonResponse(200, map[string]any{
			"ok":       true,
			"service":  "digital-terrarium",
			"ruleset":  "cycle-v1",
			"time":     time.Now().UTC().Format(time.RFC3339),
		}), nil
	}

	if id == "" {
		return jsonResponse(400, map[string]string{"error": "habitat id required"}), nil
	}

	seed := time.Now().UnixNano()
	if raw := os.Getenv("TERRARIUM_SEED"); raw != "" {
		if parsed, err := strconv.ParseInt(raw, 10, 64); err == nil {
			seed = parsed
		}
	}

	switch method {
	case "GET":
		return jsonResponse(200, defaultHabitat(id, seed)), nil
	case "PUT":
		var habitat Habitat
		if err := json.Unmarshal([]byte(request.Body), &habitat); err != nil {
			return jsonResponse(422, map[string]string{"error": "invalid habitat state"}), nil
		}
		habitat.ID = id
		habitat.UpdatedAt = time.Now().UTC().Format(time.RFC3339)
		return jsonResponse(200, habitat), nil
	case "POST":
		habitat := defaultHabitat(id, seed)
		if request.Body != "" {
			_ = json.Unmarshal([]byte(request.Body), &habitat)
		}
		return jsonResponse(200, advance(habitat)), nil
	case "DELETE":
		return jsonResponse(202, map[string]string{"status": "habitat scheduled for composting"}), nil
	default:
		return jsonResponse(405, map[string]string{"error": "method not allowed"}), nil
	}
}

func main() {
	// The production build wraps route with aws-lambda-go/lambda.Start.
	// Keeping the ecological core dependency-light makes it easy to test locally.
	_, err := route(context.Background(), Request{
		RawPath: "/health",
		RequestContext: RequestContext{HTTP: HTTPContext{Method: "GET", Path: "/health"}},
	})
	if err != nil && !errors.Is(err, context.Canceled) {
		panic(err)
	}
}
