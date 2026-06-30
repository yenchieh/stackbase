import { createApp } from 'vue'
import App from './App.vue'
import { initAnalytics } from './analytics'

initAnalytics() // no-op unless VITE_UMAMI_* are set
createApp(App).mount('#app')
