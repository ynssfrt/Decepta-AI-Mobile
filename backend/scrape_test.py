import asyncio
from playwright.async_api import async_playwright

async def main():
    async with async_playwright() as p:
        browser = await p.chromium.launch(headless=True)
        page = await browser.new_page()
        url = 'https://www.hepsiburada.com/beta-kids-yildizlari-sayabilir-misin-susie-linn-p-HBCV0000AVDJUW-yorumlari'
        await page.goto(url)
        await page.wait_for_timeout(3000)
        
        # Scroll to bottom to trigger any load
        await page.evaluate("window.scrollTo(0, document.body.scrollHeight)")
        await page.wait_for_timeout(2000)
        
        # Extract comments
        comments = await page.locator('[class*="ReviewCard"]').all_inner_texts()
        print(f"Total ReviewCards found on Page 1: {len(comments)}")
        
        # Check total ratings and reviews from DOM
        try:
            rating_count = await page.locator('[itemprop="ratingCount"]').get_attribute('content')
            print(f"Rating count: {rating_count}")
        except Exception as e:
            print("Rating count parse error:", e)
            
        await browser.close()

asyncio.run(main())
