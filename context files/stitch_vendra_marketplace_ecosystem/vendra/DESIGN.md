---
name: Vendra
colors:
  surface: '#f8f9ff'
  surface-dim: '#cbdbf5'
  surface-bright: '#f8f9ff'
  surface-container-lowest: '#ffffff'
  surface-container-low: '#eff4ff'
  surface-container: '#e5eeff'
  surface-container-high: '#dce9ff'
  surface-container-highest: '#d3e4fe'
  on-surface: '#0b1c30'
  on-surface-variant: '#464651'
  inverse-surface: '#213145'
  inverse-on-surface: '#eaf1ff'
  outline: '#777682'
  outline-variant: '#c7c5d3'
  surface-tint: '#5257a5'
  primary: '#232774'
  on-primary: '#ffffff'
  primary-container: '#3b3f8c'
  on-primary-container: '#acb0ff'
  inverse-primary: '#bfc1ff'
  secondary: '#9d4300'
  on-secondary: '#ffffff'
  secondary-container: '#fd761a'
  on-secondary-container: '#5c2400'
  tertiary: '#003a16'
  on-tertiary: '#ffffff'
  tertiary-container: '#005422'
  on-tertiary-container: '#35d168'
  error: '#ba1a1a'
  on-error: '#ffffff'
  error-container: '#ffdad6'
  on-error-container: '#93000a'
  primary-fixed: '#e1e0ff'
  primary-fixed-dim: '#bfc1ff'
  on-primary-fixed: '#0a0b5f'
  on-primary-fixed-variant: '#3a3e8b'
  secondary-fixed: '#ffdbca'
  secondary-fixed-dim: '#ffb690'
  on-secondary-fixed: '#341100'
  on-secondary-fixed-variant: '#783200'
  tertiary-fixed: '#6bff8f'
  tertiary-fixed-dim: '#4ae176'
  on-tertiary-fixed: '#002109'
  on-tertiary-fixed-variant: '#005321'
  background: '#f8f9ff'
  on-background: '#0b1c30'
  surface-variant: '#d3e4fe'
typography:
  h1:
    fontFamily: Inter
    fontSize: 40px
    fontWeight: '700'
    lineHeight: '1.2'
    letterSpacing: -0.02em
  h2:
    fontFamily: Inter
    fontSize: 32px
    fontWeight: '700'
    lineHeight: '1.25'
    letterSpacing: -0.01em
  h3:
    fontFamily: Inter
    fontSize: 24px
    fontWeight: '700'
    lineHeight: '1.3'
  body-lg:
    fontFamily: Inter
    fontSize: 18px
    fontWeight: '400'
    lineHeight: '1.5'
  body-md:
    fontFamily: Inter
    fontSize: 16px
    fontWeight: '400'
    lineHeight: '1.5'
  body-sm:
    fontFamily: Inter
    fontSize: 14px
    fontWeight: '400'
    lineHeight: '1.5'
  label-md:
    fontFamily: Inter
    fontSize: 14px
    fontWeight: '600'
    lineHeight: '1.2'
  label-sm:
    fontFamily: Inter
    fontSize: 12px
    fontWeight: '500'
    lineHeight: '1.2'
rounded:
  sm: 0.25rem
  DEFAULT: 0.5rem
  md: 0.75rem
  lg: 1rem
  xl: 1.5rem
  full: 9999px
spacing:
  base: 8px
  xs: 4px
  sm: 8px
  md: 16px
  lg: 24px
  xl: 32px
  2xl: 48px
  container-margin: 20px
  gutter: 16px
---

## Brand & Style

This design system is engineered to foster deep trust and seamless utility within the Pakistani multi-vendor landscape. The brand personality is professional and dependable, yet infused with the vibrant energy of a bustling marketplace. It balances corporate reliability—essential for financial transactions—with a warm, accessible layer that resonates with both urban and rural users.

The visual style follows a **Corporate / Modern** movement. It prioritizes clarity, high-fidelity execution, and a "mobile-first" philosophy to cater to the predominant device usage in the region. By utilizing generous whitespace and a structured information hierarchy, the design system ensures that complex multi-vendor inventories remain digestible and easy to navigate.

## Colors

The palette is anchored by **Deep Indigo**, a color chosen to project stability and institutional trust, reminiscent of established financial entities. This is contrasted by **Warm Orange**, which serves as the primary action driver, highlighting call-to-actions, discounts, and "Add to Cart" functions with high visibility.

The neutral scale utilizes cool-tinted grays to maintain a crisp, clean aesthetic against the soft #F8F9FF background. Semantic colors for success, warning, and error follow international standards but are tuned for high legibility against white surfaces, ensuring that critical status updates regarding orders and payments are unmistakable.

## Typography

This design system utilizes **Inter** for its exceptional legibility on digital screens and its neutral, systematic character. Headings are set with a bold weight (700) to provide a clear structural anchor for product categories and vendor names. 

The base body size is set at 16px to ensure accessibility across various demographics. For Urdu localization, the system should maintain equivalent line-height ratios to accommodate the taller descenders of the Nastaliq or Naskh scripts, ensuring that bilingual content remains harmonious and readable.

## Layout & Spacing

The layout is built on a **fixed-width grid** for desktop (12 columns) and a **fluid grid** for mobile (2 or 4 columns). A strict 8px spatial rhythm governs all padding and margins, ensuring vertical rhythm and visual consistency across disparate vendor shopfronts.

In this design system, the standard container margin for mobile is 20px to prevent content from feeling cramped on smaller devices, while a 16px gutter provides enough breathing room between product cards in a grid view. Use the 'lg' (24px) spacing for separating distinct logical sections on a page.

## Elevation & Depth

Visual hierarchy in this design system is achieved through **ambient shadows** and **tonal layering**. Surfaces use a soft, diffused shadow (0 2px 12px rgba(0,0,0,0.08)) to lift cards off the light blue background without creating harsh edges.

Depth is used functionally:
1. **Level 0 (Background):** #F8F9FF – The base canvas.
2. **Level 1 (Cards/Surface):** #FFFFFF with default shadow – Used for product listings and vendor profiles.
3. **Level 2 (Overlays):** #FFFFFF with increased shadow spread – Used for modals, dropdowns, and mobile navigation menus.

This approach creates a sense of "physical" stacks that help users understand the relationship between the marketplace UI and the specific merchant content.

## Shapes

The shape language of this design system is defined by a mix of "Rounded" and "Pill" geometries. 

- **Cards and Containers:** Use a 16px radius to evoke a modern, friendly feel.
- **Buttons:** Use an 8px radius to maintain a sense of precision and professional intent.
- **Status Pills & Badges:** Use a 24px radius (full pill) to distinguish them clearly from interactive buttons and static cards.

This differentiation in corner radius helps users subconsciously categorize elements: large rounds are for content containers, medium rounds for actions, and full rounds for informational metadata.

## Components

### Buttons
Primary buttons use the Deep Indigo background with white text for high-importance actions like "Proceed to Checkout." Secondary actions use the Warm Orange to draw attention to specific marketplace opportunities. All buttons utilize the 8px border radius.

### Input Fields
Inputs feature a 1px border (#E2E8F0) and a subtle 4px internal padding. On focus, the border shifts to Deep Indigo with a soft outer glow. Error states must be accompanied by both a red border (#EF4444) and an icon to assist users with color-blindness.

### Product Cards
The hallmark of the marketplace, these cards use the 16px radius and the standard shadow. Images should have a subtle inner border to prevent "bleeding" into the white card surface when the product photo has a light background.

### Chips & Badges
Utilized for categories (e.g., "Electronics", "Fashion") and status (e.g., "In Stock"). These follow the 24px pill shape. Category chips should use a light tint of the primary color with dark text for a sophisticated look.

### Vendor Headers
A specialized component featuring the vendor's logo, rating, and "Follow" button. This component should utilize a slightly darker background or a subtle border to distinguish the shop's identity from the general marketplace.