import { expect, test, type Page } from '@playwright/test'

const png = Buffer.from(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAusB9Y9ZQmcAAAAASUVORK5CYII=',
  'base64',
)

test.beforeEach(async ({ page }) => {
  await page.addInitScript(() => {
    Object.defineProperty(window, 'AudioWorkletNode', { value: undefined })
  })
})

async function addShots(page: Page, names = ['first.png', 'second.png']) {
  await page.locator('input[type="file"]').setInputFiles(
    names.map((name) => ({ name, mimeType: 'image/png', buffer: png })),
  )
}

test('keeps shortcut guidance behind the info control', async ({ page }) => {
  await page.goto('/')
  await addShots(page)

  await expect(page.locator('kbd:visible')).toHaveCount(0)
  await page.getByRole('button', { name: 'Keyboard shortcuts' }).click()
  await expect(page.getByRole('heading', { name: 'Keyboard shortcuts' })).toBeVisible()
  await expect(page.locator('kbd:visible')).not.toHaveCount(0)
})

test('deletes a carousel image and keeps a valid selection', async ({ page }) => {
  await page.goto('/')
  await addShots(page)

  await page.getByRole('button', { name: 'Delete first.png' }).click()

  await expect(page.getByText('1 / 1')).toBeVisible()
  await expect(page.getByAltText('second.png')).toBeVisible()
  await expect(page.getByRole('button', { name: 'Delete first.png' })).toHaveCount(0)
})

test('navigates with arrows while the note field remains focused', async ({ page }) => {
  await page.goto('/')
  await addShots(page)

  const note = page.getByRole('textbox', { name: 'Note for first.png' })
  await note.fill('Draft note')
  await note.press('ArrowRight')

  await expect(page.getByText('2 / 2')).toBeVisible()
  await expect(page.getByRole('textbox', { name: 'Note for second.png' })).toBeFocused()
})

test('shows a desktop-only notice on mobile screens', async ({ page }) => {
  await page.setViewportSize({ width: 390, height: 844 })
  await page.goto('/')

  await expect(page.getByRole('heading', { name: 'Redpen is made for desktop.' })).toBeVisible()
  await expect(page.locator('input[type="file"]')).toHaveCount(0)
})

test('links to the public source repository', async ({ page }) => {
  await page.goto('/')

  await expect(page.getByRole('link', { name: 'View source code' })).toHaveAttribute(
    'href',
    'https://github.com/HMDRAMS-DEV/redpen',
  )
})

test('rejects active image formats', async ({ page }) => {
  await page.goto('/')
  await page.locator('input[type="file"]').setInputFiles({
    name: 'active.svg',
    mimeType: 'image/svg+xml',
    buffer: Buffer.from('<svg xmlns="http://www.w3.org/2000/svg"><script>alert(1)</script></svg>'),
  })

  await expect(page.getByRole('alert')).toHaveText(
    'Use PNG, JPEG, or WebP screenshots up to 25 MB each.',
  )
  await expect(page.getByText('Drop your screenshots anywhere')).toBeVisible()
})
