<script setup lang="ts">
import { ref, onMounted } from 'vue'
import { getHealth, getMe } from './api'

const health = ref('checking…')
const token = ref('')
const me = ref<unknown>(null)
const meError = ref('')

onMounted(async () => {
  try {
    health.value = JSON.stringify(await getHealth())
  } catch (e) {
    health.value = `error: ${(e as Error).message}`
  }
})

async function loadMe() {
  me.value = null
  meError.value = ''
  try {
    me.value = await getMe(token.value)
  } catch (e) {
    meError.value = (e as Error).message
  }
}
</script>

<template>
  <main>
    <h1>stackbase</h1>

    <section>
      <h2>/healthz <small>public</small></h2>
      <pre>{{ health }}</pre>
    </section>

    <section>
      <h2>/me <small>JWT-protected</small></h2>
      <input v-model="token" placeholder="paste a JWT" />
      <button @click="loadMe">GET /me</button>
      <pre v-if="me">{{ me }}</pre>
      <p v-if="meError" class="err">{{ meError }}</p>
    </section>
  </main>
</template>

<style scoped>
main { font-family: system-ui, sans-serif; max-width: 40rem; margin: 2rem auto; padding: 0 1rem; }
small { color: #71717a; font-weight: 400; font-size: .8rem; }
pre { background: #f4f4f5; padding: .75rem; border-radius: .375rem; overflow-x: auto; }
input { padding: .4rem; width: 60%; }
button { padding: .4rem .8rem; margin-left: .5rem; }
.err { color: #b91c1c; }
</style>
