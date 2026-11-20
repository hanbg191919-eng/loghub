import { api } from './client'
import type { TagCount } from '../types'

/** 사용 중인 태그와 게시물 수 (많이 쓰인 순) */
export const fetchTags = () => api<TagCount[]>('/api/tags')
