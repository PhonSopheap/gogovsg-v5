import { LinkStatistics } from '../../../../shared/interfaces/link-statistics'
import { DeviceType } from '.'

export interface LinkStatisticsRepository {
  /**
   * Retrieves link statistics for a specified short link.
   *
   * @param shortUrl The target short url to retrieve link statistics.
   * @param offsetDays The number of days of daily clicks stats to load.
   */
  findByShortUrl(
    shortUrl: string,
    offsetDays?: number,
  ): Promise<LinkStatistics | null>

  /**
   * Update link statistics of the specified short url.
   *
   * @param shortUrl The short url statistics to update.
   */
  updateLinkStatistics: (shortUrl: string, device: DeviceType) => void
}
