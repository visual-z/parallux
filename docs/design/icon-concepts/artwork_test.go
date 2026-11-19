// The offline review sheet uses SVG references. A missing reference still
// occupies 18 pt in the browser, so counting icons alone can hide empty states.
package iconconcepts

import (
	"bytes"
	"encoding/xml"
	"os"
	"sort"
	"strings"
	"testing"
)

type svgDrawing struct {
	XMLName   xml.Name
	ID        string       `xml:"id,attr"`
	Href      string       `xml:"href,attr"`
	Transform string       `xml:"transform,attr"`
	Attrs     []xml.Attr   `xml:",any,attr"`
	Children  []svgDrawing `xml:",any"`
}

func TestEveryMenuBarStateResolvesToDistinctArtwork(t *testing.T) {
	page, err := os.ReadFile("index.html")
	if err != nil {
		t.Fatal(err)
	}
	start := bytes.Index(page, []byte(`<svg class="sprite"`))
	if start < 0 {
		t.Fatal("the menu bar drawings are missing")
	}
	var sprite struct {
		Defs svgDrawing `xml:"defs"`
	}
	if err := xml.NewDecoder(bytes.NewReader(page[start:])).Decode(&sprite); err != nil {
		t.Fatal(err)
	}
	byID := make(map[string]svgDrawing)
	for _, drawing := range sprite.Defs.Children {
		byID[drawing.ID] = drawing
	}

	// Include placement: two identical pieces can form different marks by moving.
	var contours func(svgDrawing, string, int) string
	contours = func(node svgDrawing, position string, depth int) string {
		t.Helper()
		if depth > len(byID) {
			t.Fatal("cyclic SVG reference")
		}
		position += node.Transform
		if node.Href != "" {
			ref, ok := byID[strings.TrimPrefix(node.Href, "#")]
			if !ok {
				t.Fatalf("missing drawing %s", node.Href)
			}
			return contours(ref, position, depth+1)
		}
		switch node.XMLName.Local {
		case "path", "rect", "circle", "ellipse", "polygon", "polyline", "line":
			parts := []string{position, node.XMLName.Local}
			for _, attr := range node.Attrs {
				parts = append(parts, attr.Name.Local+"="+attr.Value)
			}
			sort.Strings(parts)
			return strings.Join(parts, " ")
		}
		var paths []string
		for _, child := range node.Children {
			paths = append(paths, contours(child, position, depth+1))
		}
		return strings.Join(paths, "|")
	}

	for _, concept := range []string{"rails", "cut", "phase"} {
		seen := make(map[string]string)
		for _, state := range []string{"disconnected", "balance", "bond", "failover", "degraded"} {
			art := contours(byID[concept+"-"+state], "", 0)
			if art == "" {
				t.Fatalf("%s has no artwork for %s", concept, state)
			}
			if previous, ok := seen[art]; ok {
				t.Fatalf("%s uses the same contours for %s and %s", concept, previous, state)
			}
			seen[art] = state
		}
	}
}
