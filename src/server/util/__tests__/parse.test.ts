import { extractShortUrl } from '../parse'

jest.mock('../../config', () => ({
  ogHostname: 'test.gov.sg',
}))

describe('extractShortUrl tests', () => {
  test('should extract shorturl with full url and https header', () => {
    expect(extractShortUrl('https://test.gov.sg/my-url')).toStrictEqual(
      'my-url',
    )
  })
  test('should not extract shorturl without https header', () => {
    expect(extractShortUrl('test.gov.sg/my-url')).toStrictEqual(null)
  })
})
